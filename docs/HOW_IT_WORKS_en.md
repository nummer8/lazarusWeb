# How lazarusWeb Works — A Detailed Explanation

> For anyone reading this codebase for the first time: these three things — "LCL controls + server + browser rendering" — are explained as one continuous thread.
> Written 2026-11-11 · based on the code snapshot at that time (27 units in `src/core`, 13226 lines; line counts are only a snapshot and are not continuously updated in this document)
> Companion documents: `ARCHITECTURE_en.md` (module inventory, default Alpine layer + optional Ext layer, including 2.14 mobile adaptation), `NOTES.md` (a record of 163 pitfalls), `MAPPING_en.md` (control mapping tables)
> **This article takes the default Alpine.js layer (`src/client/lw-alpine.js`) as its main thread.**
> The optional Ext layer (`lw.js`) uses exactly the same JSON protocol, reconcile, and event/push channels,
> differing only in DOM construction and the styling system: enable explicitly with `--client=ext`; when unspecified, Alpine is preferred.

---

## 0. First, dispel a misconception

The question most often asked on first contact is: "Is this server-side rendering or browser rendering?"

The answer is **neither**. In this framework:

> **There is only one control tree, and it is on the server. The browser has no controls — only "mirrors" of controls.**

So there is no such thing as "two rendering systems coexisting." What actually happens is **one serialization + one reconciliation**:

```
Server LCL control tree  ──serialize──►  JSON snapshot  ──render──►  Browser native DOM component tree (Alpine, default)
       ▲                        {id,kind,      ▲                  │
       │                         props,       │                  │  (optional Ext layer: Ext component tree)
       │                         children}    │                  │
       └──────────── event {id, ev, val} ◄─────┴──────────────────┘
```

- `lwwriter.pas` handles rightward movement (tree → JSON)
- `lw-alpine.js` (default) handles further rightward movement (JSON → native DOM/Alpine components) and leftward movement (events → JSON);
  the optional Ext layer uses `lw.js` for the same responsibilities, with the protocol unchanged
- `lwdispatch.pas` handles the far left (JSON → real LCL event invocation)

Once you understand this, everything else is detail. And the reason the details are complex all stems from one decision: **use real LCL controls, not shadow controls**.

---

## 1. Why this approach works: three premises

### 1.1 `TLWForm` is a genuine `TForm` descendant

Not a proxy class, not a shadow class, not a wrapper. `TLWForm = class(TForm)`, so:

- The `TButton` / `TEdit` you drag onto the IDE are LCL's own controls;
- `.lfm` files load as-is; the property inspector, `Align`, `TabOrder`, and the events tab all work normally;
- The layout you arrange in the designer **is** the layout in the browser (same coordinate system; `Align` is
  recomputed by the frontend `runLayout`. Note: `Anchors` does not do frontend snapping calculations; see the
  known limitations in `AUDIT_LFM_en.md` — revised 2026-11-13).

The only line business code needs to change:

```pascal
TMainForm = class(TLWForm)   // originally class(TForm)
```

This is the source of "100% business code reuse," and also the common root of all the benefits and all the troubles of this entire approach.

### 1.2 `--ws=nogui`: giving LCL a "graphics card with no screen"

The server is compiled with the nogui widgetset; controls are **really created, really hold properties, and really store event method pointers** — they just are not drawn.

But nogui's "graphics card" is crippled: there are many places in LCL that assume "there is a screen, a window handle, and a message loop." `lwws.pas` (333 lines) patches these. The four most typical crash points:

| Crash point | Root cause | Patch |
|---|---|---|
| AV on creating any `TForm` | `TCustomForm.AfterConstruction` reads `Monitor.PixelsPerInch`; under nogui `EnumDisplayMonitors` returns False and `Monitor = nil` | `TLWWidgetSet = class(TNoGUIWidgetSet)` supplies a virtual monitor (1920×1080 @96DPI) |
| Hard cast crash on `Application.DoubleBuffered` | nogui's widgetset instance is not a `TWSCustomForm` descendant; `adbDefault` falls into the hard cast `TWSCustomFormClass(WidgetSetClass)` | Explicit `adbFalse` in `LWInstallWidgetSet` |
| AV on loading an lfm with `TMainMenu` | nogui's `RegisterMainMenu` etc. all return False, the menu WS class is not registered, and `TWSMenuClass(WidgetSetClass)` gets nil | Register LCL empty implementation classes as placeholders; menus are rendered by the browser instead |
| `Form.Show` division by zero | Real `Show` goes through `ShowWindow → SetWindowPos`, relying on screen pixel calculations | `TLWForm.SetVisible` intercepts, translating to `SessionShowForm`, **never falling through to inherited** |

The last one has a condition that must be noted: the interception must exclude `csLoading in ComponentState`; otherwise the step that assigns the initial `Visible` value while loading `.lfm` is also intercepted, leaving LCL's internal state inconsistent (division by zero when creating the form).

> **This is the cost of the "real control tree" route**: it saves rewriting hundreds of controls, at the price of having to cater to every implicit assumption LCL makes.

### 1.3 Fake GDI: where do text metrics come from

More subtle than the "virtual monitor": `Canvas.TextWidth`, `AutoSize`, and `GetTextMetrics` all depend on GDI under nogui, and GDI does not exist. `lwws.pas` therefore replaces the entire set of GDI calls with **estimates**:

```pascal
function TLWWidgetSet.GetTextExtentPoint32(DC: HDC; Str: PChar; Count: Integer;
  var Size: TSize): Boolean;
begin
  h := CurFontPx;                              // font height of the most recent CreateFontIndirect
  Size.cx := Max(1, Round(Count * h * 0.55));  // width ≈ character count × font height × 0.55
  Size.cy := Round(h * 1.25) + 3;
  Result := True;
end;
```

Design handles are fake too: `CreateCompatibleDC` returns the constant `HDC(1000)`, `SelectObject` returns 0, and `GetDeviceCaps` always returns 96 for `LOGPIXELSX`.

This estimate is enough to keep LCL's internal layout code from crashing and to give `AutoSize` a reasonable width, but it **does not recognize glyph differences** — `0.55` is a coefficient taken from average Western character width, while the actual width of Chinese/full-width characters is about 1.0 times the font height. So:

> **For `AutoSize` labels containing Chinese, the width computed on the server may be too narrow.** (Inferred from the code, not measured control by control.)
> When a label is truncated, first check whether "the server computed it too narrow" or "browser-side styling squeezed it," rather than going straight to editing CSS.

Understanding this layer makes clear why the documentation repeatedly stresses "in Web mode, layout follows designer dimensions" — the server only has one set of approximate metrics; pixel-level fidelity relies on absolute coordinates, not on text reflow.

---

## 2. The complete round trip of a click

Taking `LWHandleEvent` at `lwdispatch.pas:769` as the main thread:

```
Browser                                     Server (fphttpserver, one thread per request)
  │                                        │
  │ 1. click → collect {id, ev, val}        │
  │    plus the vals of all inputs in the same form
  ├──────── POST /lw/api/event ───────────►│
  │                                        │ 2. LWApplyFieldSnapshot writes back other controls' values
  │                                        │ 3. LWApplyValue writes val into the target control
  │                                        │ 4. LWInvokeEvent → RTTI → OnClick
  │                                        │ 5. business code executes (it thinks it is on the desktop)
  │                                        │ 6. BuildPayload serializes the new tree
  │◄──────── 200 {sid, forms:[...]} ───────┤
  │ 7. applyPayload → syncChildren reconcile│
  │    only patches changed nodes           │
```

The three core lines of code after the server receives the request:

```pascal
LWApplyFieldSnapshot(S, JGetObj(AReq,'vals'), id);  // ① first write back the latest values of other inputs in the same form
LWApplyValue(c, AReq);                              // ② write val into the event target control
LWInvokeEvent(c, ev, row, col);                     // ③ RTTI finds the method pointer and calls it
```

### 2.1 Why ① is needed (a bug that really existed)

The default rendering layer (`lw-alpine.js`, same for the optional Ext layer) only sends back a value when a control **has an `OnChange` handler attached**. So an edit box without `OnChange` stays forever at the initial `Text` it had at construction time on the server —

So on a login form: the user types a password → clicks "Login" → the server validates an **empty/stale password** → wrong credentials still pass.

The fix is to have the browser attach "the current values of all input controls in the same form" (`vals`) to every event it sends, and have the server write them all back **before** dispatching the event. Note that the event target control (`SkipId`) must be skipped; its own value is handled by ③ via `val`.

`LWIsSnapField` also deliberately excludes data-aware controls (`TDBEdit` / `TDBMemo` / …): behind them are dataset fields, and writing `Text` directly is equivalent to modifying data; they must go through the `OnSetFieldValue` / `Edit-Post` channel.

### 2.2 ③ RTTI dispatch, and "buttons cannot use RTTI directly"

The standard reflection path is:

```pascal
PP := GetPropInfo(C, AEv);
if (PP = nil) or (PP^.PropType^.Kind <> tkMethod) then Exit;
M := GetMethodProp(C, PP);
if not Assigned(M.Code) then Exit;
TNotifyEvent(M)(C);
```

But buttons must go through the native `Click` first:

```pascal
if (AEv = 'OnClick') and (C is TButton) then
begin
  TButton(C).Click;   // Click handles ModalResult internally, then calls OnClick
  Exit(True);
end;
```

The reason lies in the line `if ModalResult <> mrNone then Form.ModalResult := ModalResult` inside `TCustomButton.Click`. **This is the real mechanism by which a modal dialog closes when you click "OK."** Bypassing `Click` and calling the method pointer directly leaves nogui with no message loop to take over, and `ShowModal` hangs until timeout.

Similar special cases: `TDBGrid`'s `OnTitleClick` / `OnCellClick` have the signature `(Column: TColumn)` rather than `TNotifyEvent`, so a hard cast will corrupt the stack; `TDBNavigator`'s `OnClick` is a two-argument event, and `BtnClick` itself triggers it internally.

**This is the most important conclusion in the whole article**: `Click`, `ModalResult`, `TSpeedButton`'s group-exclusive `SetDown`, `DataSource`'s field binding — **all are LCL's native implementation**. The framework merely replaces "the user's hand" from a mouse with a piece of JSON. So "LCL controls are really running" is not a figure of speech.

---

## 3. Serialization: why you cannot do a "full RTTI dump"

`lwwriter.pas` (1594 lines) looks like it merely reads properties, but most of its code is **supplying semantics on LCL's behalf**. The skeleton is simple:

```pascal
function WriteControl(C: TControl): TJSONObject;
begin
  kind := KindOf(C);                      // 70+ branches, order-sensitive
  o := MakeBase(C, kind);                 // id/kind/name/x/y/w/h/align/caption/ev/...
  WriteKindProps(C, kind, o);             // per-control-type specific properties
  o.Add('children', WriteChildren(...));  // recursion
end;
```

All the difficulty lies in four places.

### 3.1 `KindOf` is order-sensitive

The inheritance relationships in `lcl/interfaces` make "if by type from top to bottom" give wrong results:

- `TRadioGroup` / `TCheckGroup` fall into the `TGroupBox` branch;
- `TCheckListBox` falls into `TListBox`;
- `TValueListEditor` falls into `TStringGrid`;
- The `TDateEdit` family are `TCustomEditButton` (`TCustomEdit` descendants); without checking first, they degrade into plain `edit`, and also leak the internal `TEdit` + `TSpeedButton` as two stray nodes;
- `TToggleBox` is a `TCustomCheckBox` descendant, not a `TButton`; its semantics are "can stay pressed" — rendered as `button` with `Checked` sent down as `down`.

So the order of every `else if` in `KindOf` (`lwwriter.pas:97`) has a reason; changing the order silently changes the rendering result.

### 3.2 Internal controls pollute the control tree

LCL's `TStringGrid` really contains a `TStringCellEditor`, `TRadioGroup` really contains a bunch of `TRadioButton`s, and `TTabControl` really contains a `TCustomNotebook`. They are all in `Controls[]`; serializing them recursively directly makes the browser sprout dozens of unnamed stray nodes (gray boxes at `(0,0)`).

`IsInternalControl()` (`lwwriter.pas:72`) is a blacklist that names them one by one.

### 3.3 A property's "literal value" is not the "user intent"

- `TPanel` / `TToolBar`'s `Caption` defaults to the control name → must not be rendered (`CaptionOf` discards it when `s = C.Name`);
- `TShape`'s fill color is in `Brush.Color`; `TControl.Color` is an invalid property for it; reading only `Color` yields an empty string → **white background, white border, the control "disappears"**;
- The `TLWClickEvent` whitelist decides which events are sent down: only those with a genuinely attached method pointer (`Assigned(M.Code)`) are written into `ev`, avoiding the browser sending a bunch of events nobody handles.

### 3.4 Some properties read as "fake values" under nogui

The most typical is the form's client area size: when the handle has not been created, `ClientWidth` returns the construction default 320×240 instead of the 1020×680 in the `.lfm`. The browser pads the height to that size, and the window shrinks to 277px.

```pascal
if AForm.HandleAllocated then
begin
  o.Add('cw', AForm.ClientWidth);
  o.Add('ch', AForm.ClientHeight);
end
else
begin
  o.Add('cw', AForm.Width);      // Width is accurate only when the handle does not exist
  o.Add('ch', AForm.Height);
end;
```

---

## 4. Browser side: not "rendering," but "reconciliation"

### 4.1 reconcile

After the new tree arrives, `applyPayload` → `syncChildren` (default layer in `lw-alpine.js`, optional Ext layer in `lw.js`) reconciles by `id`, with three branches:

```js
list.forEach(function (n) {
    var c = S.comps[n.id];
    if (c && c.__lwParent === ct) patchNode(c, n);        // already exists → only change differing properties
    else { if (c) destroyNode(n.id); createNode(n, ct); } // added/reparented → rebuild
});
old.forEach(function (id) { if (!keep[id]) destroyNode(id); });  // disappeared → destroy
```

Two immediate benefits:

- **Input focus is not lost**: no unchanged component instance is touched, the caret stays where it was;
- **No full-page refresh**: only differing nodes are patched.

The same applies at the form level: forms not present in `p.forms` are directly `close + destroy` (the server deleted the form, so the browser follows).

### 4.2 Layout: design-time coordinates are the baseline; the default layer adapts on top of them

LCL is **absolute coordinates + `Align`/`Anchors`**; it has no CSS flow layout. So the frontend first positions absolutely by `x/y/w/h`, `runLayout` computes `Align` itself, and recomputes on container `resize`
— **it does not hand layout over to the browser's flexbox** (`Anchors` does not do frontend snapping calculations; see `AUDIT_LFM_en.md`).
This is the price of "pixel-perfect reproduction of the designer."

Unlike the optional Ext layer, **the default Alpine layer provides frontend adaptation on top of this**: it determines the layout mode from viewport width/touch capability, and works with form templates (desktop `<form name>.html`, mobile `<form name>.m.html`,
marked in the file header with `lw-tpl-mode`) to produce either a floating-window or full-page flat view; templates serve only as a background layer,
**they do not reflow controls** — controls are always drawn at their design-time absolute coordinates. On mobile, `.m.html` is preferred;
when no template is configured, WYSIWYG from design time is preserved (mobile uses pan mode).
See `ARCHITECTURE_en.md` 2.14 for the mechanism and `MANUAL_en.md` chapter 16 for usage.

### 4.3 Push channel

- Events: `POST /lw/api/event`, with the response carrying the new tree directly (synchronous), or via a WS frame;
- Push: **long polling is the only push channel** (`GET /lw/api/poll?after=N`). WebSocket
  (`/lw/ws`) carries only event requests/responses; push always goes out via the long-polling cursor, automatically falling back to HTTP on disconnect
  (the final wording of pit 33, revised 2026-11-13 — the older version of this section that said "`/lw/ws` push preferred" is obsolete);
- Cursor protocol: the push queue carries a `seq`; each tab fetches its own via `poll?after=N` (this is mandatory when multiple tabs share one session);
  dialog commands also carry `to=<tab>` for targeting, so only the initiating tab pops the dialog;
- Session: `sid` is stored in **sessionStorage** (tab-level; closing the tab invalidates it = next open returns to the login page),
  a refresh stays in the same session; expiry returns 410 + `gone` (the browser uses this to automatically create a new session and return to the login page).

---

## 5. The most counterintuitive part: `ShowModal` really does block

On the desktop, `if f.ShowModal = mrOk then ...` relies on a **nested message loop**. The server has no message loop, and nogui does not even have windows. The solution is to swap in something "that can block":

```
Event request thread (fphttpserver, one thread per request)
  │
  ├─ business code calls ShowModal
  ├─ pushes the modal command into the session's outbound queue (with seq) → SetEvent wakes long polling/WS
  ├─ TEvent.WaitFor(200)          ← wakes every 200ms, only to check for timeout
  │
  └─ browser clicks close → POST /lw/api/dlg → FDlgDone.SetEvent → thread wakes and returns ModalResult
```

Key implementation: `ShowModalInSession` at `lwsession.pas:587`; the wait loop is at `lwsession.pas:246`.

Why 200ms slices instead of a single `WaitFor(180000)`? The source comment says it clearly: waiting a full 180 seconds makes it impossible to check for timeout mid-way or to respond to session cleanup.

So **`if f.ShowModal = mrOk then ...` really waits for the user to click**, with no change to business code.

The price is that the request thread is occupied (up to 180 seconds) and other requests in the same session have to queue — which happens to match the desktop semantics of "you cannot click elsewhere during a modal." In addition, business code that **manually** assigns `ModalResult := mrOk` must also be able to close the window, so `LWHandleEvent` adds one more step after event dispatch:

```pascal
mf := S.ModalForm;
if (mf <> nil) and (mf.ModalResult <> mrNone) then
  S.SessionEndModal(mf, mf.ModalResult);
```

---

## 6. Thread model overview

```
fphttpserver (one thread per request)
 ├─ event request thread: write back values → RTTI triggers business → blocks here at TEvent.WaitFor during ShowModal
 ├─ long polling / WS push: session outbound queue with seq, each tab fetches its own cursor
 ├─ Sweep thread: expired session cleanup
 ├─ TLWServerThread (GUI build): accept loop in a background thread
 └─ panel TTimer (GUI build): main thread periodically swaps the log buffer (no Synchronize)
```

Corollaries (must be known for deployment):

- All sessions live in **process memory**, with no external Redis → clustering can only rely on **sticky sessions** (`ip_hash` / `lwhyper`'s sid stickiness);
- Each online user has **one complete control tree**, so memory grows linearly with user count;
- Each event is **one HTTP round trip** — unnoticeable on a LAN, but noticeably sluggish on public mobile networks.

---

## 7. Comparison with the other two approaches

| | Server-side rendering (fpWeb) | Browser-side rendering (pas2js/WASM) | **This approach** |
|---|---|---|---|
| Where are the controls | None (only WebModule + templates) | Browser (LCL logic compiled to JS/wasm) | **Server (real LCL tree)** |
| What the browser gets | HTML strings | A compiled program | **Control tree JSON** |
| Where is the state | Stateless (via Session/hidden fields) | Browser | **Server session memory** |
| Cost per event | One full HTTP round trip | 0 (local) | One HTTP/WS round trip |
| Business code reuse | 0 (UI logic must be rewritten) | Partial (browser controls need adaptation) | **100% (change one base class line)** |
| `.lfm` / designer | Unusable | Needs conversion | **Usable as-is** |
| Extend with a new control | Write a template | Write a browser-side control implementation | **Write one `KindOf` + one rendering branch** |
| Good for | Admin backends, reports, SEO | Interaction-heavy SPAs, offline | **Moving LAN desktop systems to the browser** |

The cost advantage of this approach in "extending new controls" comes from the choice in section 1.3: **treat Ext JS as the browser-side widgetset**. Instead of writing browser implementations for hundreds of controls yourself, you "translate" each LCL control onto a mature control library — the workload changes from "rewrite controls" to "write a mapping table + write reconciliation logic."

The price is that the two sets of semantics do not fully align (absolute positioning vs Ext layout, `ModalResult` vs Ext window, `Items` vs Ext store), and every misalignment needs a dedicated serialization branch. Most of `lwwriter.pas`' 1594 lines are these.

---

## 8. Boundaries and known limitations

**Scenarios where this approach should not be used**: newly written systems aimed at the public internet, requiring responsive/mobile layouts and SEO. It is a "runtime for webifying desktop programs," not a general-purpose Web framework.

**Built-in limitations** (see `ARCHITECTURE_en.md` §3.7):

- Modal timeout of 180 seconds; only one dialog at a time per session;
- `TOpenDialog` cannot browse the server's disk (only "select file → upload");
- `TSplitter` supports dragging (sends back displacement → server SetSplitterPosition rearranges neighbors by Align, pit 186); `TUpDown/TProgressBar/TTrackBar` write back `Position` on the browser side;
- High DPI is handled at the virtual monitor's 96 DPI; `.lfm` designed at 125%/150% will be scaled back to 96;
- Unadapted controls appear as placeholder gray boxes in the browser (see `CONTROL_MATRIX_en.md` for support levels);
- Direct PDF output is currently replaced by the browser's "Save as PDF."

---

## 9. If you want to read the code, read in this order

| Order | File | What to look at | Key locations |
|---|---|---|---|
| 1 | `src/core/lwws.pas` | The foundation of the whole approach: virtual monitor + fake GDI | `TLWWidgetSet` L56, `GetTextExtentPoint32` L184 |
| 2 | `src/core/lwform.pas` | How `TLWForm` intercepts `Visible` | `SetVisible` |
| 3 | `src/core/lwsession.pas` | Sessions, form list, outbound queue, modals | `BuildPayload` L527, `ShowModalInSession` L587 |
| 4 | `src/core/lwwriter.pas` | Tree → JSON: whitelist, internal controls, special cases | `KindOf` L97, `MakeBase` L241, `WriteControl` L1461, `WriteForm` L1507 |
| 5 | `src/core/lwdispatch.pas` | Events → RTTI: write back, dispatch, button special case | `LWInvokeEvent` L662, `LWHandleEvent` L769 |
| 6 | `src/client/lw-alpine.js` (default) | Reconcile, layout, event capture, push, templates and mobile adaptation | `syncChildren` / `runLayout` / `applyPayload` / `lwFetchTpl` |
| 7 | `src/core/lwhttp.pas` | Route table, static assets, upload/download | Route dispatch |
| 8 | `src/client/lw.js` (optional Ext layer) | Same responsibilities as item 6, identical protocol | `createNode` / `syncChildren` / `runLayout` |

**The fastest way to verify** is not reading code, but running a demo and printing the JSON:

```bat
build.bat hello
demos\hello\hello.exe --port=8090 --verbose
```

Open `http://127.0.0.1:8090/` in the browser, then `curl "http://127.0.0.1:8090/lw/api/tree?sid=<your sid>"` to see what the tree really looks like — more intuitive than any document.

---

## 10. One-sentence summary

> It does not render twice. It treats the **LCL control tree** as the single source of truth, the **default Alpine.js layer's native DOM** (optionally the Ext component layer) as a "display" that can be refreshed remotely, and the **HTTP request thread** as a message loop that can block. With these three things in place, the execution model of a desktop program is completely reproduced in the browser.

---

## Appendix: three common misunderstandings

1. **"The browser is running LCL"** — No. The browser has not a single line of Pascal; by default it runs Alpine.js-driven native DOM (or Ext JS with the optional Ext layer). LCL runs only in the server process.
2. **"Every event rebuilds the whole tree"** — The server does re-serialize the whole tree (`BuildPayload`), but the browser reconciles by `id`, and only differing nodes are patched; focus and input state are preserved.
3. **"`ShowModal` is a browser-side popup"** — No. The server thread really is waiting; the browser is merely what it waits on. Refreshing or closing the tab in the browser makes it wait until the 180-second timeout.

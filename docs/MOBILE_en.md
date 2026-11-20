# Mobile Browser Adaptation: Feasibility Analysis → Plan B Implementation Record

> Status: **Implemented** (2026-11-16, Plan B: adaptive detection + form template + pan fallback).
> Sections 1–7 are the pre-implementation feasibility analysis archive; Section 8 records the
> Plan B implementation at the time, of which the "DOM relocation / `{%control name%}` placeholder /
> single-column flow" parts **have been replaced by the new mechanism**.
> **Current state (since 2026-11-18)**: window and flat modes share a single
> `<root>\tpl\<form name>.html`; the file header `lw-tpl-mode:window|flat` determines the
> rendering method (flat takes priority); the template serves only as a background decoration
> layer, it **does not rearrange controls**, which are always absolutely positioned by the LFM's
> `Left/Top`. The IDE Tools menu generates this file with one click from a .lfm.
> The current state is governed by `MANUAL_en.md`, Part 2, Chapter 16; the analysis is based on
> the Alpine rendering layer (`?client=alpine`, currently the default); the Ext version does not apply.

## Conclusion Summary

| Question | Answer |
|---|---|
| Can it technically run in a mobile browser? | **Yes**. The foundation is already there (viewport meta + viewport adaptation chain + zoom fallback); existing forms open without blank screens or layout corruption, and buttons are clickable |
| Can it be "good to use"? | No, it is missing three framework-level pitfalls (virtual keyboard, font legibility, touch details) plus one architectural limitation (LCL absolute coordinates do not reflow) |
| Recommended route | Light use → Plan 1 (compatibility pack, a few small changes); mobile as the primary client → Plan 1 + Plan 3 (business dual forms); do not spend the long term on "flow reflow" |
| This decision | ~~Not for now~~ → **Implemented 2026-11-16**: took Plan B with self-developed template placeholders (detection in the browser + DOM relocation template + pan fallback), see Section 8 |

---

## 1. Foundation Already in Place (Almost Zero Changes)

| Current state | Code location | Significance for mobile |
|---|---|---|
| `<meta name="viewport" content="width=device-width, initial-scale=1">` | `lwhttp.pas` BuildIndexHtml / BuildAlpineHtml (two places) | Mobile does not render with a 980px virtual viewport, 1:1 layout |
| Main form canvas follows the viewport: resize debounce 160ms → send `OnResize{w,h}` → server `SetBounds` → differential return | `lw-alpine.js` `sendViewResize()` / `window.addEventListener('resize')`; `lwdispatch.pas` `LWApplyFormResize` | Triggered by portrait/landscape switching and address bar show/hide; align children are reflowed by the client's `runLayout` |
| Zoom fallback: when the canvas is still larger than the viewport, CSS `transform: scale()` fits it on one screen | `lw-alpine.js` `fitMainZoom()` | Fixed-size forms also produce no page scrollbar |
| All interactions use native `click`/`blur`/`change` | `lw-alpine.js` control branches | Touch taps synthesize click; buttons/inputs/dropdowns are **basically usable** |
| Main form maximized by default, drag corners/dragging disabled | `lw-alpine.js` `buildForm`'s `isMain` branch (pitfall 112) | No "dragging half a screen" misalignment on mobile |

**Key architectural facts** (which determine the ceiling):

- nogui forms have no handle, LCL does not compute align on the server — layout relies entirely on the client's `runLayout` reflow;
- `runLayout` only recomputes **align children** (`alClient`/`alTop`, etc.), **controls with hard-coded `Left/Top` do not reflow**;
- under `Scaled=True`, LCL pixels = CSS pixels 1:1 (the server's `SetBounds` is the seen size).

Therefore the current "adaptation" only solves "canvas size follows the viewport", not "controls are rearranged".

## 2. Gap Analysis: Three Framework-Level Pitfalls

### Pitfall 1: Virtual Keyboard Triggers resize (Most Practical)

- Android Chrome keyboard pops up → `window.innerHeight` drops sharply → goes through `resize` debounce → `sendViewResize` → server flattens the form → keyboard closes and it bounces back, **oscillating back and forth**;
- iOS Safari is more troublesome: `innerHeight` stays unchanged, the keyboard directly covers the lower half of the screen, and the focused input is invisible.

Fix idea: use `visualViewport.height` for the judgment instead; only treat it as a real resize when the height difference exceeds a threshold (e.g. >120px); under iOS, call `scrollIntoView({block:'center'})` on the input when it is focused. Changes are concentrated in `sendViewResize()` and the resize listener.

### Pitfall 2: Font Illegible After Zooming

- Portrait 390px holding a 960–1800px desktop form, scale ≈ 0.4, 12px text becomes **4.8px**;
- this is the essential limitation of absolute coordinate layout; `fitMainZoom` can only scale proportionally, not reflow.

Fix idea (choose one):
- set a lower zoom limit for `fitMainZoom` (e.g. `s >= 0.55`); below the limit allow vertical page scrolling and rely on the user's two-finger zoom;
- or use Plan 2/3 to make the content truly adapt to the width.

### Pitfall 3: Touch Details

- When an iOS input's font size is <16px, focusing automatically zooms the whole page → under the mobile breakpoint raise the font size of `.lw-input` etc. to 16px;
- recommend adding `touch-action: manipulation` to clickable elements to eliminate the double-tap zoom judgment delay;
- dragging (title bar `mousedown`/`mousemove`) does not trigger on touch dragging — mobile generally does not need to drag windows, so it can be left unhandled; the main form already has dragging disabled, so no impact.

## 3. Three Plans

| | Plan 1: Mobile Compatibility Pack | Plan 2: Mobile Flow Layout | Plan 3: Business Dual Forms |
|---|---|---|---|
| Approach | Fix the 3 pitfalls above: visualViewport keyboard judgment, zoom lower limit, iOS font size + touch-action | When width < breakpoint (e.g. 768px) `runLayout` takes the mobile branch: ignore absolute coordinates, stack controls vertically, stretch width to full | Server selects the mobile-version LFM by UA/parameter, coexisting with the desktop version; the framework only provides the Plan 1 fallback |
| Amount of change | Small (3 places in `lw-alpine.js` + CSS) | Medium (add a branch to the client layout engine) | Large (one mobile design per business form) |
| Effect | Existing forms "viewable and clickable", layout still desktop-shaped, squeezed into the screen by zoom | Forms with regular align work well; old forms dense with absolute coordinates have unpredictable results | A genuine mobile experience on mobile |
| Risk | Low | Medium: every business form must be verified on real devices one by one | Low (framework untouched), cost is on the business side |
| Suitable for | Occasionally checking data and clicking buttons on a phone | Few forms, regular layout, unwilling to make a second LFM | Mobile is the primary client |

**The fatal flaw of Plan 2**: LCL's layout semantics are absolute coordinates; forcing a reflow in `runLayout` amounts to reinventing a layout engine on the client, and it cannot know the semantic grouping between controls (who should be on the same row), so the result is purely heuristic. Not recommended as a long-term route.

## 4. Recommended Route

1. **Short term (if to be done)**: Plan 1. Three small changes, immediate benefit, zero impact on the desktop side (the breakpoint/`visualViewport` judgments can all take effect only on narrow screens or when the difference exceeds the threshold).
2. **Medium term (if to be used as a mobile client)**: Plan 1 + Plan 3. Design a mobile-version LFM separately for core business forms, leaving the desktop version untouched.
3. **Not recommended**: treating Plan 2 as a general solution.

## 5. If Implemented in the Future: Change List (Plan 1)

| File | Change |
|---|---|
| `src/client/lw-alpine.js` | `sendViewResize()`: use `visualViewport` to judge the keyboard (height difference >120px does not trigger server resize); `fitMainZoom()`: add a lower zoom limit and an "allow vertical scrolling" branch; `scrollIntoView` on input focus |
| `src/client/lw-alpine.css` | Narrow-screen breakpoint (`@media (max-width: 768px)`): input control font size ≥16px, `touch-action: manipulation` |
| `demos/gallery/lw/` | Synchronized copy (pitfall 109: `lw/` next to the exe takes priority over `src/client`) |

After changes are complete, verify according to Section 6 and run regression on `t_gallery` (50 items).

## 6. Verification Method (Simulate with CDP Before Real Devices)

```bash
# Equivalent environment for 150% system scaling (the user's machine has this configuration)
msedge.exe --headless=new --remote-debugging-port=9223 \
  --user-data-dir=<temp directory> --force-device-scale-factor=1.5 \
  --window-size=1800,1200 "http://127.0.0.1:8099/?client=alpine"
```

Checklist (take values with `Runtime.evaluate`):

| Metric | Expected |
|---|---|
| `.lw-win`'s `offsetWidth/offsetHeight` | == viewport size (or handled per the zoom lower limit) |
| `document.documentElement.scrollWidth/scrollHeight` | == viewport (no page scrollbar) |
| `getComputedStyle(.lw-win).transform` | non-`none` when fallback is needed, and scale is reasonable |
| Keyboard simulation | after changing `visualViewport`/window height the canvas does not move (Pitfall 1 fix effective) |
| Input font size | ≥16px on narrow screens |

Note (corrected on retest 2026-11-16): under Edge 157 + `--headless=new`,
`Emulation.setDeviceMetricsOverride` **took effect in all 8 scenarios**, `innerWidth` exactly
equals the set value, and `mobile:true` together with the viewport meta yields a 1:1 CSS
viewport; see `tests/cdp_device_probe.py` for evidence. Earlier records of "sometimes it does
not take effect" mostly stemmed from older browsers or from taking values before the page
finished loading; if "innerWidth unchanged" still reproduces on your machine, fall back to the
`--force-device-scale-factor` + `--window-size` launch parameters, and always take values with
`Runtime.evaluate` after the page has loaded. When screenshots are in physical pixels,
CSS size = physical size / dpr.

## 7. Terminology and Limitation Memo

- **CSS viewport**: `window.innerWidth/innerHeight` (excluding browser UI); this is what `sendViewResize` sends, with the height further reduced by 28px for the title bar;
- **LCL pixels = CSS pixels**: holds under `Scaled=True`; the server's `SetBounds` needs no PPI conversion;
- **Minimum form size**: the server's `LWApplyFormResize` lower limit is 240×180; impossible on narrow screens (<240px), but it pushes the zoom lower-limit logic to an extremely small value;
- **Mobile background**: WebSocket may disconnect when the page is frozen/backgrounded; the existing reconnect/self-healing mechanism (lwhyper inspection + client resync) can cover it, but the first frame after reactivation needs real-device verification.

## 8. Plan B Adaptive Detection and Mobile Template (Designed and Implemented 2026-11-16)

> Applicability: this section records Plan B of 2026-11-16 (placeholder + DOM relocation);
> the detection strategy (8.1–8.5) is still valid, the template interface (8.6) has been changed
> to a background decoration layer, see the annotations below.
> This section fixes the detection strategy and the measured basis.
> Baseline correction: the `sendViewResize()` / `fitMainZoom()` in the Section 1 table do not
> exist in the current `src/client/lw-alpine.js` (a repository-wide search hits only this
> document); the existing chain has only `ResizeObserver` (:2609-2611); the CDP note in
> Section 6 has been corrected according to the retest results.

### 8.1 Conclusion: Judge "Layout Mode", Not "Device"; Put Detection in the Browser

Plan B's template moves the already-built control DOM into placeholders in the browser; the
server does not participate in the selection, so **there is no need to identify mobile devices
on the Pascal side**. The question that really needs answering is "should the flow template be
enabled right now", which is determined by the available width: dragging a desktop window down
to 420px likewise cannot fit a 1200px absolutely positioned form, and a phone in landscape at
844px should still stay in the flow layout. Keep the three quantities separate, do not compress
them into one boolean:

| Quantity | Value | Basis | Use |
|---|---|---|---|
| layout | `mobile` / `desktop` | width breakpoint + hysteresis | whether to apply the template, whether to skip `placeNode` / `runLayout` |
| input | `touch` / `mouse` | `(any-pointer: coarse)` and `(hover: none)` both true | touch details (font size ≥16px, `touch-action`, tap target ≥44px), independent of layout |
| capability | keyboard / orientation / zoom | `visualViewport`, `orientation` | fallback for Pitfalls 1/2 in Section 2, not involved in mode detection |

### 8.2 Signal Priority

| Layer | Signal | Measured reliability | Use |
|---|---|---|---|
| Hard override | `?layout=desktop\|mobile\|auto` in the URL (the client reads `location.search` directly, no server change needed; reading request parameters is described in `lwhttp.pas`'s query-string parsing), `sessionStorage['lw-layout']` | definite | manual switching by the user, demos, troubleshooting |
| Main criterion | `matchMedia('(max-width: 834px)')` / `('(min-width: 1100px)')` + hysteresis zone | high (all correct in 8 scenarios read now) | layout |
| Input criterion | `any-pointer: coarse` + `hover: none` | high (UA spoofing does not change it) | input |
| Auxiliary | `orientation`, `visualViewport.height` | medium | portrait/landscape, keyboard fallback |
| Weak signal | UA keywords, `navigator.userAgentData.mobile` | low | statistics / logs / first-screen hints only, not involved in detection |
| Disabled | `navigator.maxTouchPoints > 0` | measured as 10 on desktop headless | cannot be used as a touch basis |

### 8.3 Measured Data (`tests/cdp_device_probe.py`, Edge 157 headless)

| Scenario | innerW×H | coarse | UA contains Mobile | UAD.mobile | Judgment |
|---|---|---|---|---|---|
| Desktop baseline | 1200×900 | no | no | false | desktop |
| Desktop narrow window (size changed only) | 420×900 | no | no | false | **mobile** |
| Full phone simulation | 390×844 | yes | yes | false | mobile |
| UA spoofed only | 1200×900 | no | yes | false | **desktop** |
| iPad portrait | 820×1180 | yes | yes | false | mobile |
| Desktop touchscreen | 1200×900 | yes | no | false | desktop (but input=touch) |
| Foldable external screen | 280×653 | yes | yes | false | mobile |
| Phone landscape | 844×390 | yes | yes | false | mobile (hysteresis zone, touch takes priority) |

Other measured facts: the viewport meta takes effect (a 390px viewport renders 1:1,
`visualViewport.scale=1`); the first-screen request header contains **only `User-Agent`**, no
`Sec-CH-UA-*` at all; `userAgentData.mobile` is constantly `false` in all 8 scenarios (it does
not update when CDP overrides the UA), which further shows it cannot be used as the main
criterion.

### 8.4 Self-Developed Detection Code (All Web Standard APIs)

> Below is a simplified version synchronized with `src/client/lw-alpine.js:2191-2236`; the
> complete implementation of template fetching and DOM relocation is in the source code.

```js
var TPL_MQ_IN = '(max-width: 834px)';
var TPL_MQ_OUT = '(min-width: 1100px)';
var TPL_KEY = 'lw-layout';      /* ?layout= / sessionStorage hard override */
var layoutState = null;         /* null / 'desktop' / 'mobile' */
var tplCache = {};              /* template string cache; 404 is also cached as null */

function lwIsTouch() {
    return matchMedia('(any-pointer: coarse)').matches &&
           matchMedia('(hover: none)').matches;
}
function lwLayoutNow() {
    var force = null;
    try {
        force = new URLSearchParams(location.search).get('layout') ||
                sessionStorage.getItem(TPL_KEY);
    } catch (e) { }
    if (force === 'desktop' || force === 'mobile') return force;
    var enter = matchMedia(TPL_MQ_IN).matches;
    var leave = matchMedia(TPL_MQ_OUT).matches;
    if (layoutState === null) {
        if (enter) return 'mobile';
        if (leave) return 'desktop';
        return lwIsTouch() ? 'mobile' : 'desktop';
    }
    if (enter) return 'mobile';
    if (leave) return 'desktop';
    return layoutState;                            /* keep for 835~1099 */
}
function lwApplyLayout() {
    var want = lwLayoutNow();
    if (want === layoutState) return;
    layoutState = want;
    document.documentElement.setAttribute('data-lw-layout', want);
    document.documentElement.setAttribute('data-lw-input', lwIsTouch() ? 'touch' : 'mouse');
    lwRelayout(want);                              /* implemented: relocate DOM by target mode */
}
var pending = false;
function lwSchedule() {                           /* events are only triggers, state is always read fresh */
    if (pending) return;
    pending = true;
    requestAnimationFrame(function () { pending = false; lwApplyLayout(); });
}
[TPL_MQ_IN, TPL_MQ_OUT, '(any-pointer: coarse)', '(orientation: landscape)'].forEach(function (q) {
    var mq = matchMedia(q);
    if (mq.addEventListener) mq.addEventListener('change', lwSchedule);
});
window.addEventListener('resize', lwSchedule);
window.addEventListener('orientationchange', lwSchedule);
if (window.visualViewport) visualViewport.addEventListener('resize', lwSchedule);
lwApplyLayout();
```

### 8.5 Why "Events Are Only Triggers, State Is Read Fresh"

Dynamic switching measured (inject a listener on the same page and continuously change the viewport):

| Action | State read fresh | Events actually dispatched |
|---|---|---|
| 1200 → 390 portrait | `narrow=1 coarse=1 hoverNone=1` | `resize`×2, `vv`×2, `orient=0`; **`narrow=1` change was NOT dispatched** |
| 390 → 844 landscape | `narrow=0 landscape=1` | `resize`, `vv`, `narrow=0`, `orient=1` |
| 844 → 960 hysteresis zone | `narrow=0 wide=0` | `resize`, `vv`; no change for pointer change |
| 960 → 1200 | `wide=1` | `resize`, `vv`, `wide=1` |

Conclusion: `matchMedia`'s `change` may be missed on the first breakpoint change or on pointer
capability changes, while `resize` / `visualViewport.resize` are dispatched repeatedly in
groups; therefore **you cannot read `e.matches` inside the event to decide state**, you must read
fresh every time and deduplicate with `requestAnimationFrame` (add 120–160ms debouncing if
necessary, consistent with the existing `ResizeObserver` chain), and use the hysteresis zone to
eliminate back-and-forth jumping. The main criterion is width; keyboard popping up only changes
height, and `lwApplyLayout()` returns idempotently, making it naturally immune to the height
oscillation of Pitfall 1 in Section 2.

### 8.6 Interface with the Template Layer (Implemented, Implementation Points)

- **【Current state 2026-11-18】** `lwRelayout(mode)` no longer moves any control DOM:
  the template is inserted as a `.lw-tpl.lw-tpl-backdrop` background layer at the very front
  of the client area, controls remain in the form's kids absolutely positioned by the LFM's
  `Left/Top`; `S.P[id]` / `S.E[id]` are unchanged, and event ids, Alpine directives and
  incremental patches all work as usual (the invariant of pitfall 149 is preserved).
- **【Current state】** the desktop template `<form name>.html` (shared by window and flat
  modes in one file), the mobile template `<form name>.m.html` (mobile read-only, without a
  template it falls back directly to LCL layout); when the file header is `lw-tpl-mode:flat`,
  `lwApplyFlatTpl` hides the title bar/drag corner, fills the viewport, and the page scrolls by
  itself; with `window` it keeps the original floating-window geometry. Neither mode adds
  `lw-flow` or skips `placeNode` / `runLayout`; both templates serve only as background
  decoration layers.
- **【Current state】** when a template is missing or parsing fails, the whole thing falls back
  to the design-time layout; the old `.flat.html` still triggers flat mode according to the
  compatibility rule (flat takes priority).
- **【Current state】** after applying `.m.html` on mobile, the template is only a decoration
  layer: controls keep their design-time absolute positioning, and the form also **keeps its
  design width and height** (when the design size is smaller than the viewport it stretches to
  fill the viewport); content exceeding the viewport is viewed by panning/scrolling through
  `#lw-root` (`fm.tplFallback=true`). You cannot compress the form width to
  `min(design width, viewport width)`: after narrowing, tab sheets reflow at the narrower width
  and controls in the right-hand TPageControl get clipped to blank space (pitfall 179). With no
  `.m.html`, it falls back directly to LCL layout (it does not read the desktop `.html`).
- **【Current state】** under mobile layout, the theme entry is unified as a draggable floating
  button at the bottom right, `.lw-theme-fab` (mounted in both window mode and flat mode):
  the 22px icon in the 28px title bar is too imprecise for a finger; window mode under desktop
  layout still uses the title bar icon, mobile layout hides that one with CSS, and desktop
  layout automatically removes the floating button (`themeEntrySync` corrects idempotently on
  layout/template switching).
- The following is the original 2026-11-16 plan record, for historical reference only: the
  template's internal column count/spacing/font size is left to the template's own `<style>`;
  when a placeholder does not match a control `Name`, the whole thing falls back.
- **Fallback forms without a template do not do overall proportional scaling** (finalized
  2026-11-16): a fit-width scheme with `transform: scale((innerWidth-8)/design width)` was once
  implemented and verified, but compressing a 1200 design width onto a 390 screen leaves the
  font at only 0.32×, effectively unreadable — the user decided to abandon it. Nor do we hard
  compress the form to the viewport width: after narrowing, child controls are still placed at
  design coordinates, the right side is clipped/blank, and dragging the form only moves the
  blank space (real-device screenshot feedback). **Finalized as pan mode**: the form keeps its
  design width and height (font at original size, stretching to fill the viewport when the
  design size is smaller than the viewport), with `left=0` fixed and title bar dragging
  forbidden; content exceeding the viewport is viewed by scrolling/panning through `#lw-root`
  — `lwUpdatePan()` toggles `html[data-lw-pan]` according to whether a fallback form exists,
  with CSS `html[data-lw-pan="1"] #lw-root { overflow:auto }` on the CSS side;
  `lwFallbackSize` recomputes with the viewport on rotation/window resize/keyboard popping up
  (mounted on `lwScheduleLayout` every frame). For single-column usability on small screens,
  provide a mobile template for the form.
- In mobile mode the form keeps its design width and height and enables panning (`savedPos`
  stores left/width/height, restored when switching back to desktop; `top` fixed at 6px),
  and the status bar sticks to the bottom of the form; when switching, if there is input focus,
  it is deferred until blur or the focus is retained.
- Hard overrides: URL `?layout=desktop|mobile` and `sessionStorage['lw-layout']`, readable and
  writable at runtime via `LW.layout.set()/get()`; implemented in the Alpine layer only, the
  Ext layer is a component tree and does not apply.

### 8.7 Server and Authorization Boundaries

- **Zero server change**: `?layout=` is only an optional hard override, going through the existing `QueryP`.
- If the business side really needs to use UA for statistics: on this machine fcl-web 3.3.1
  measured `ARequest.UserAgent` as having a value;
  `ARequest.GetCustomHeader('User-Agent')` returns **empty** (standard headers do not enter
  CustomHeaders; the project's existing custom-header reading approach only applies to custom
  headers and cannot be used to read User-Agent).
- The first-screen request header has no Client Hints such as `Sec-CH-UA-Mobile`; obtaining them
  requires the server to send `Accept-CH` and the browser to support it, and the first request
  is usually still missing them — insufficient to carry layout detection.

### 8.8 Remaining Items (Real-Device Verification Items, Out of This Scope)

Under CDP simulation, `(any-pointer: coarse)` has stickiness after turning off touch, and
`maxTouchPoints` is non-zero on desktop, so pointer capabilities need to be rechecked on real
devices; the relationship between the iOS keyboard and `visualViewport`, two consecutive resizes
when switching foldables, and the first frame after background freeze all need real-device
verification.

Also note a **test-harness artifact** (not a product defect): if `clearDeviceMetricsOverride`
is called before CDP changes the viewport size, the viewport momentarily returns to the real
window width (1200, hitting the exit breakpoint), and the hysteresis zone keeps the wrongly
locked desktop until the next size; real-device rotation is a direct jump between 390↔844,
without passing through intermediate widths. When simulating, simply stack the new
`setDeviceMetricsOverride` on top (`cdp_fit_scale.py`'s `metrics()` is written this way).

---

Related: `NOTES.md` pitfall 111 (viewport adaptation chain), pitfall 112 (main form maximized +
cache fingerprint), `DEBUGGING_en.md` (CDP evidence-gathering methodology).

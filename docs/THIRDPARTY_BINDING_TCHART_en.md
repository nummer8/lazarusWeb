# Example: Binding the Real Third-Party Control TAChart's TChart into lazarusWeb

> This is a **complete example you can follow**. For a mechanism overview, see `docs/THIRDPARTY_BINDING_en.md`; this article focuses on one specific control — `TChart` from the third-party chart package **TAChart** bundled with Lazarus — through the whole process from "can be constructed" to "draws a chart in the browser". All class names, properties, field names, source locations, and line numbers in this article are taken from local measurements on 2026-11-19 (`C:\111\lazarus` + `C:\lazarusWeb\src`), not placeholder examples.

---

## 0. Why Choose TChart as the Example

"Binding a third-party control" is often talked about as empty talk, because many third-party controls cannot even pass the server's first gate. First look at the measured screening results — this is the reason for choosing it:

| Real third-party control | Package | nogui compile | Can serve as server-side instance |
|---|---|---|---|
| **TAChart / TChart** | `tachartlazaruspkg.lpk` | ✅ passes (43693 lines) | **Yes**, the protagonist of this article |
| SynEdit / TSynEdit | `synedit.lpk` | ✅ passes (122409 lines) | Yes (drawing-type, discussed separately) |
| VirtualTreeView / TLazVirtualStringTree | `laz.virtualtreeview_package.lpk` | ❌ fails | Cannot be constructed directly, see §7 |

Measured commands and output (kept verbatim):

```
$ lazbuild -B --ws=nogui tachartlazaruspkg.lpk
(1008) 43693 lines compiled, 7.6 sec
CHART_EXIT=0

$ lazbuild -B --ws=nogui laz.virtualtreeview_package.lpk
delphicompat.pas(140,2) Fatal: (2013) Cannot open include file "uses.inc"
Error: Compile required packages failed: laz.virtualtreeview_package 5.5.3.1
EXIT=2
```

TChart wins on three points: **constructible under nogui**, **a clear data model** (Series → point set), and **the framework's existing `chart` kind SVG renderer can be reused directly** — it explains the data contract between "server-side control" and "browser picture" most clearly.

---

## 1. First See the Chain That Must Be Completed

lazarusWeb does not move control pixels to the browser, but is a "real server-side LCL control tree + browser rendering by `kind`". For TChart to display, the following must be completed:

```
TChart (real server-side control, constructed under nogui)
   │  KindOf(TChart)              → 'tachart'
   │  WriteKindPropsBody          → convert Series/XValue/YValue to JSON
   ▼
JSON node {kind:'tachart', charttype, title, categories, series}
   │  lw-alpine.js innerOf()      → reuse chartSvg(n) to draw the SVG
   ▼
Browser DOM (<svg> line/bar/pie chart)
   │  (the chart is read-only: no value write-back in this example)
   ▼
No write-back needed → do not touch LWApplyValue / IsLWClickEvent
```

**This judgment is important**: TChart is a pure display control; on the browser side there is no need for "the user drags the chart back to modify data", so this example **does not need** the event whitelist and value write-back. This is exactly the two categories of third-party control binding:

- **Read-only display type** (charts, gauges, images): only the three steps ①②③ are needed (construct → kind → property sending → rendering).
- **Editable input type** (number boxes, date boxes, trees): beyond the three steps, events, write-back, and incremental update must also be added.

This article chooses the read-only display type because it best focuses on explaining the core "data bridging", with little code and easy verification.

---

## 2. Step 0: First Verify nogui Can Construct It (Don't Skip)

**This is the step that should be done first among all work.** If a third-party control depends on Win32 handles, native Canvas, or TImageList, it will throw an exception on construction under the headless nogui widgetset. If you change six places of code and only then discover it cannot be constructed, all the earlier work is wasted.

I wrote a 52-line probe (`tests/vtchart_probe/probe.lpr`) to test with the real TChart API: construct → set title → add Series → add data points → read back. The result file, verbatim:

```
create ok: TChart 400x240 series=0
title=月度销量
seriescount=1
series0.title=销量
series0.count=3
  pt[0] x=0 y=12
  pt[1] x=1 y=19
  pt[2] x=2 y=15
```

Conclusion: `TChart.Create`, `Title.Text.Text`, `TLineSeries.Create`, `AddXY`, `SeriesCount`, `S.Count`, `XValue[i]`, `YValue[i]` are **all usable** under nogui. The probe project itself is also a reusable template, at path `tests/vtchart_probe/`.

Two real API pitfalls encountered in the probe, noted first (§6 expands on them):

1. You must `uses Interfaces, Forms, Graphics` — `Application`/`clRed` come from `Forms`/`Graphics` respectively; missing either gives `Identifier not found`.
2. The static type of `Ch.Series[0]` is `TBasicChartSeries`, which **has no** `.Title/.Count` members; to read data you must hold a concrete subclass variable (e.g. `S: TLineSeries`) and then read `S.Count`.

---

## 3. Step 1: Make the Control Compilable and Instantiable from lfm

### 3.1 Add Package Dependency

TChart is in the `tachartlazaruspkg` package. Add it to the two runtime packages and the business project:

- `src/lwcore.lpk`: add an item `<PackageName Value="tachartlazaruspkg"/>` to `<RequiredPkgs>`
- `src/lwserver.lpk`: same
- Business `.lpi`: add `<PackageName Value="tachartlazaruspkg"/>` to `Packages/RequiredPackages`

The real `<RequiredPkgs>` structure (`lwserver.lpk:110`):

```xml
<RequiredPkgs Count="3">
  <Item1><PackageName Value="LCL"/></Item1>
  <Item2><PackageName Value="FCL"/></Item2>
  <Item3><PackageName Value="lwcore"/></Item3>
</RequiredPkgs>
```

After adding TChart, change `Count` to 4 and add `Item4`.

> If you only want instances created purely in code (no lfm drag-and-drop), you can skip the lfm-related steps and directly do `TChart.Create(Self)` in code.

### 3.2 Register the Class So lfm Can Stream It

When `object Chart1: TChart` appears in lfm, the class must be findable by name at runtime, otherwise `Class TChart not found` is reported. Register it in the `initialization` section of a unit that is always `uses`d (modeled on `RegisterClass(TLWChart)` at `lwchart.pas:175`):

```pascal
uses ..., TAGraph;   // TChart is in unit TAGraph (defined at tagraph.pas:184)

initialization
  RegisterClass(TChart);
end.
```

⚠️ Don't expect `RegisterClassAlias` to substitute — pitfalls 29/41 in `docs/MAPPING_en.md` overturned the early alias approach: whichever class name the lfm stores, that class name itself must be registrable.

---

## 4. Step 2: Add a Branch to `KindOf` (Derivation Order Sensitive)

Location: `src/core/lwwriter.pas:196` `function KindOf(C: TControl): string;`

Add a line:

```pascal
  else if C is TChart then Result := 'tachart'
```

**Where to place it matters.** `KindOf` is a long `if ... else if` chain, and **derived classes must come before ancestors**. `TChart` inherits from `TCustomChart` → `TCustomControl`, does not conflict with the `TEdit/TPanel` family, so theoretically it won't be stolen wherever it goes; but the framework convention groups custom/third-party controls in the front part of the chain (together with `TLWChart`, `TLWCaptcha`, see `lwwriter.pas:220-227`). The safe approach: insert right near the `TLWChart` branch.

Memory rule for comparison: **if your control is a descendant of `TEdit`/`TPanel`/`TCustomControl`, its branch must be inserted before the corresponding ancestor check**, otherwise it is intercepted by a generic branch and only half the properties are sent. Although TChart is a `TCustomControl` descendant, there is no bare `TCustomControl` fallback branch in `KindOf`, so it is safe. (VirtualTreeView is not so lucky — it is a `TCustomControl` descendant and would be stolen if placed after generic controls.)

Naming the new kind `tachart` instead of reusing `chart` is to avoid touching the framework's own `TLWChart` logic; the rendering layer then explicitly reuses its `chartSvg`, giving the best of both worlds.

---

## 5. Step 3: Send Properties (Core: Bridging Series into JSON)

Location: `src/core/lwwriter.pas` `procedure TLWWriter.WriteKindPropsBody`, the `chart` branch is around line 1910. Add a `tachart` branch modeled on it. The target JSON must align **word for word** with the renderer `chartSvg`'s fields (field names at `lw-alpine.js:908-918`):

| JSON field | Type | Source |
|---|---|---|
| `charttype` | string | `'line'`/`'bar'`/`'pie'` |
| `title` | string | `Chart.Title.Text.Text` |
| `categories` | string[] | X-axis labels (this example formats the points' X values) |
| `series` | `{name,values:number[]}[]` | each Series name + point-set Y values |

Bridging code (can be copied directly, variable names kept consistent with the framework's `chart` branch):

```pascal
  else if AKind = 'tachart' then
  begin
    { TAChart TChart → data contract of the framework chart renderer.
      Measured: TAGraph/TASeries constructible under nogui, point sets readable (see §2 probe). }
    Ch := TChart(C);
    O.Add('charttype', 'line');          // this example does line only; for multiple Series/other types see end of this section
    O.Add('title', Ch.Title.Text.Text);

    items := TJSONArray.Create;          // categories: X-axis labels
    vals  := TJSONArray.Create;          // series[0].values: Y values
    if Ch.SeriesCount > 0 then
    begin
      S := TLineSeries(Ch.Series[0]);    // type cast: see §8 pitfall 2
      for j := 0 to S.Count - 1 do
      begin
        JArrAddStr(items, FloatToStr(S.XValue[j]));
        vals.Add(S.YValue[j]);           // Double goes directly into the JSON array
      end;
    end;
    O.Add('categories', items);

    seri := TJSONArray.Create;
    b := TJSONObject.Create;
    if Ch.SeriesCount > 0 then
      b.Add('name', TLineSeries(Ch.Series[0]).Title)
    else
      b.Add('name', '');
    b.Add('values', vals);
    seri.Add(b);
    O.Add('series', seri);
  end
```

Additional local variables to declare (beyond the existing `i/j/O/items/b/vals` in `WriteKindPropsBody`):

```pascal
var
  Ch: TChart;
  S: TLineSeries;
  seri: TJSONArray;
```

And add `TAGraph, TASeries` to the unit's `uses`.

**Fault-tolerance requirement** (framework iron rule, see `THIRDPARTY_BINDING_en.md` §2.3): `S.Count = 0`, `SeriesCount = 0`, `Title.Text = nil` are all normal dirty values. The `if Ch.SeriesCount > 0` above already blocks empty Series; `Title.Text.Text` returns an empty string under nogui even when there is no title (confirmed by the probe), so it is safe. To be more robust, you can wrap the whole branch in `try/except`; the framework's `WriteControl` will degrade an exceptional control into a placeholder node with `err`, without affecting the overall payload.

**Multiple Series extension**: change the inner `for` to iterate `0..Ch.SeriesCount-1`, generating a `{name,values}` object for each Series and adding it to `seri`, consistent with the framework's `chart` branch (lines 1910-1940).

**Change chart type**: this example hardcodes `charttype='line'`. To follow TChart's real series type, just check the class of the first Series (`TLineSeries`/`TBarSeries`/`TPieSeries` are all defined in `taseries.pas` in TAChart):

```pascal
    if Ch.SeriesCount > 0 then
    begin
      if Ch.Series[0] is TPieSeries then O.Add('charttype', 'pie')
      else if Ch.Series[0] is TBarSeries then O.Add('charttype', 'bar')
      else O.Add('charttype', 'line');
    end
    else O.Add('charttype', 'line');
```

(Note: the `is` check here holds for the `TBasicChartSeries` static type; it is a type test, not member access, so it is not restricted by §8 pitfall 2. `TBarSeries`/`TPieSeries` require `uses TASeries`.)

---

## 6. Step 4: Browser Rendering (Reuse the Existing SVG Renderer)

Location: the `switch (k)` of `function innerOf(node, st)` in `src/client/lw-alpine.js`, around line 1261.

Because the JSON produced in step 5 is fully isomorphic with the framework's `chart` kind, **here a single line connects it** — make `tachart` go through the same rendering branch as `chart`:

```javascript
            case 'chart':
            case 'tachart':          // ← new: reuse the same SVG rendering
                return '<div class="lw-chart lw-boxed" id="lw-ch-' + id + '"></div>';
```

Rendering actually happens in `chartSvg(n)` (`lw-alpine.js:915`), which reads exactly the four fields `charttype/title/categories/series`. Because `tachart` nodes carry these fields, there is no need to change `chartSvg`. The content fingerprint `chartSig(n)` (line 909) also uses the same four fields, so after data changes at runtime any event coordination will automatically redraw the chart — consistent with the behavior of the in-house `TLWChart`.

**If you don't use the existing renderer**: to get TChart's native look (grid, legend, axis ticks), assemble `<svg>` or `<canvas>` yourself in `innerOf`, but note that you cannot reuse TChart's `OnPaint` pixels under nogui (`docs/THIRDPARTY_BINDING_en.md` §4.2) — all coordinates, ticks, and colors must be computed from the data yourself. This is a longer path and is not expanded in this example.

### Two Things a Read-Only Control Doesn't Need

- **No need to change `FIELD_KINDS` / `collectVal`**: the chart has no editable value.
- **No need to change `LWApplyValue` / `IsLWClickEvent`**: there is no browser→server input callback.

This is why read-only display controls have three fewer steps than input controls.

---

## 7. Step 5: Verification and Documentation

1. **Construction probe**: `tests/vtchart_probe/` provides a compilable project; after `lazbuild --ws=nogui probe.lpi`, run it and compare with `probe_result.txt` (§2). This is the fastest regression.
2. **Place a real instance**: add `object Chart1: TChart` to the lfm in `demos/audit`, set `Align=alClient`, and `AddXY` a few points in code. Use sufficient non-default properties (title, multiple Series) to avoid default values hiding problems.
3. **Rerun audit**: `tools/build_audit.bat` regenerates `docs/CONTROL_MATRIX_en.md`; confirm `TChart` is no longer an unknown gray box.
4. **Document the mapping**: add a row to `docs/MAPPING_en.md`:

   | LCL control | kind | Browser side | Event |
   |---|---|---|---|
   | TChart (TAChart) | tachart | SVG line/bar/pie (reuses chartSvg) | none (read-only) |

5. **End-to-end**: use the CDP probe in `tests/` to capture the DOM, confirm the `<svg>` exists, the `series` point count is correct, and when switching themes the chart colors follow the `lw-ch-*` classes (renderer comment at line 923: colors are carried by classes, SVG `fill` does not recognize `var()`).

---

## 8. Two Real Pitfalls You Must Know

### Pitfall 1: VirtualTreeView Fails the nogui Gate

It is the control "best suited to lazarusWeb's data model" (virtual trees supply data on demand via `OnGetText`), but **local testing shows nogui compilation fails**: it depends on package `lclextensions`, whose `delphicompat.pas` cannot find `uses.inc` under nogui (measured output in §0). If you must use it, three paths:

1. First adapt `lclextensions` to nogui (add the include path), then compile VT — heavy workload;
2. Don't instantiate VT itself, just store the tree in a normal data structure on the server, serialize the data down and render it in the browser (i.e. its own "virtual data" model, which fits lazarusWeb perfectly) — recommended;
3. Use the JS component escape hatch (`TLWHTMLFrame` + `AddAjax`), with the front end drawing the tree directly.

This is the practical significance of the "verify nogui construction first" emphasized in `docs/THIRDPARTY_BINDING_en.md` §4.1.

### Pitfall 2: The Static Type of `Ch.Series[i]` Has No Data Members

`TChart.Series` is a `TChartSeriesList`, whose elements have static type `TBasicChartSeries` — it only has generic properties like `Title`, **no** `Count`/`XValue[]`/`YValue[]`/`AddXY`. Those are on concrete subclasses `TLineSeries`/`TChartSeries` (`taseries.pas`). So:

```pascal
// ✗ won't compile: Identifier idents no member "Count"
Ch.Series[0].Count;

// ✓ hold a concrete subclass variable
S := TLineSeries(Ch.Series[0]);
n := S.Count;
```

The probe failed here on its first compile (`probe.lpr(31,3) Error: no member "Title"`); after switching to `S.Title` it passed. The bridging code in §5 already uses the correct form.

### Pitfall 3: Missing `uses` Units

The minimal `uses` for the nogui probe must include `Interfaces, Forms, Graphics`: `Interfaces` provides the widgetset, `Forms` provides `Application` (if `Application.Initialize` is called), and `Graphics` provides color constants like `clRed`. Missing any one gives `Identifier not found`.

---

## 9. One-Page Quick Reference: Read-Only Display Third-Party Control Onboarding Checklist

| # | File | Change |
|---|---|---|
| 1 | `src/lwcore.lpk`, `src/lwserver.lpk`, business `.lpi` | Add third-party package dependency (TChart → tachartlazaruspkg) |
| 2 | Common unit `initialization` | `RegisterClass(TChart)` |
| 3 | `src/core/lwwriter.pas` `KindOf` | Add `else if C is TChart then Result := 'tachart'` |
| 4 | `src/core/lwwriter.pas` `WriteKindPropsBody` | Add `tachart` branch: Series→chart JSON |
| 5 | `src/client/lw-alpine.js` `innerOf` | `case 'tachart':` reuse chart rendering |
| 6 | Verification | nogui construction probe + audit + CDP end-to-end |

**Editable input type** additionally needs: `IsLWClickEvent` (event whitelist), `LWApplyValue` (value write-back), `FIELD_KINDS`/`collectVal` (batch value collection), `patchNode` (incremental update without losing focus) — full checklist in `docs/THIRDPARTY_BINDING_en.md` §3.

---

## 10. Reference Index

| Content | Real location |
|---|---|
| Mechanism overview / six-step onboarding | `docs/THIRDPARTY_BINDING_en.md` |
| Official extension flow | `docs/MANUAL_en.md` §15 |
| kind determination | `src/core/lwwriter.pas:196` `KindOf` |
| chart property sending (copy object) | `src/core/lwwriter.pas:1910` `chart` branch |
| chart SVG renderer | `src/client/lw-alpine.js:915` `chartSvg` / `:908` `chartSig` |
| chart rendering branch | `src/client/lw-alpine.js:1631` `case 'chart'` |
| Class registration example | `src/core/lwchart.pas:175` |
| Package dependency syntax | `src/lwserver.lpk:110` `RequiredPkgs` |
| TChart class definition | `C:\111\lazarus\components\tachart\tagraph.pas:184` |
| TLineSeries / AddXY | `...\tachart\taseries.pas:245` / `tacustomseries.pas:213` |
| nogui construction probe | `tests/vtchart_probe/probe.lpr` + `probe.lpi` |
| VirtualTreeView measured failure | this article §0 / §8 pitfall 1 |

## Comparison and Selection of Three Architectures: lazarusWeb / uniGUI / IntraWeb

Although all three frameworks serve the goal of "rapidly developing web applications with Pascal/Delphi," they differ fundamentally in the nature of the server-side control tree, the rendering and communication mechanism, and the memory model.

## 🧬 Core Difference: Is the Control Tree "Real" or a "Shadow"?

This is the most fundamental distinction among the three.

- **lazarusWeb**: It runs a real LCL control tree. Through the nogui widgetset, it gives LCL a "screenless display adapter." The `TLWForm` and `TButton` you operate on the server side are genuine LCL objects. The cost is that the framework must handle all implicit assumptions LCL makes about "owning a screen" (such as fake GDI and DPI). These complexities are absorbed inside the framework.
- **uniGUI**: It uses "Shadow Classes" rather than real `TForm`. What you drag and drop in the designer are uniGUI's own wrapper controls, which map to Sencha Ext JS components but are not native VCL/LCL objects. This brings more mature commercial support and designer experience, but it also means the project is locked into the Delphi ecosystem and commercial licensing.
- **IntraWeb**: It is also based on server-side component simulation, using proprietary VCL-style components such as `TIWButton` and `TIWForm`. It maintains a complete session-level object tree on the server, but on each interaction the framework rebuilds the control tree and dispatches events. In essence, it is a kind of "stateless but simulating stateful" server-side rendering.

## 🎨 Rendering and Communication: JSON Serialization vs. Incremental Instructions vs. HTML Generation

The differences in the control tree directly lead to different front-end/back-end communication methods.

- **lazarusWeb (full JSON serialization)**: It serializes the complete server-side control tree into JSON, sends it to the browser, and Alpine.js renders it into DOM. This is an overall snapshot-style synchronization. The communication volume is relatively large, but the mechanism is direct.
- **uniGUI (incremental ExtJS instructions)**: It sends only property changes (such as `.setText("OK")`). The server-side ExtJS wrapper layer automatically generates incremental instructions, and the browser-side ExtJS engine executes the updates without DOM Diff. This is the most transmission-efficient and smoothest interaction scheme among the three, because it naturally achieves incremental updates.
- **IntraWeb (HTML generation + partial refresh)**: Its core is generating HTML. After each interaction triggers a server-side event, the framework generates new HTML (or injects scripts through a built-in JS engine to achieve partial DOM differential updates). Its output is more "traditional Web," but the granularity of interaction lies between the previous two.

## 💾 Memory Model: The Source of Pressure Is the Same, but the Magnitude Differs

The root cause is that each user session holds a control tree instance on the server. None of the three can escape this model, but the "weight" of the "control tree" differs.

- **lazarusWeb**: In memory, it holds complete real LCL control objects. Real controls usually contain heavier state and dependencies than "shadow classes." This is the necessary cost of achieving 100% Pascal business logic reuse. Memory pressure is the highest.
- **uniGUI**: In memory, it holds Delphi shadow wrappers of ExtJS components. These are lighter than real LCL controls, and incremental communication reduces serialization overhead. However, its stateful session model means the full control tree still remains resident in memory. Pressure is medium-to-high.
- **IntraWeb**: It also maintains a session-level object tree in memory, but its "control tree rebuild" mechanism and more traditional HTML rendering path make its memory model conceptually closer to traditional web sessions. However, if not managed properly, memory growth problems can also occur.

## 💎 How to Choose

- If you pursue extreme reuse of existing Pascal code (without changing a single line of business logic, only changing base classes) and can accept higher per-session memory overhead, lazarusWeb is a unique and pure choice.
- If you need production-grade interaction performance, a mature designer experience, and commercial support, and project lock-in to the Delphi ecosystem is acceptable, uniGUI's incremental ExtJS channel is the most mature engineering solution among the three.
- If you need more "traditional" web output, more flexible session storage backends (Redis/database), and relatively clear custom rendering extension points, IntraWeb is a solid middle option.

None of the three can eliminate the session memory overhead caused by the server-side control tree. This is the common cost of the fundamental route of "migrating the desktop paradigm to the Web." The only difference is how much memory cost you are willing to pay for this route in exchange for development efficiency or interaction performance.

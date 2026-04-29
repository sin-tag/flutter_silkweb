# WebF Optimization Notes (branch `webf-optimized`)

This branch reworks WebF for production-grade smoothness and ergonomics. Origin
(`https://github.com/openwebf/webf.git`) was renamed to `openwebf-upstream` so
this branch can be pushed to a fresh remote of your choosing.

## What changed

### Phase 0 — Bloat & crash hotspots (zero-risk fixes)
| Change | File | Effect |
|---|---|---|
| Add `debug-symbols/` to `.gitignore` and delete from working tree | [.gitignore](.gitignore) | Repo working tree dropped from **22 GB → 12 GB** (the historical 11 GB still lives in git history; rewrite with `git filter-repo --path debug-symbols --invert-paths` if you need to reclaim clone size). |
| `.pubignore` for the published package | [webf/.pubignore](webf/.pubignore), [.pubignore](.pubignore) | pub.dev tarball excludes tests, integration suite, vendored googletest/benchmark. |
| Fix null-unwrap on unparseable animation/transition durations | [css_animation.dart:179-188](webf/lib/src/css/css_animation.dart#L179), [transition.dart:1041-1043](webf/lib/src/css/transition.dart#L1041) | Stops the most common runtime crash when third-party CSS ships unitless time values. |
| `firstWhere` orElse for `animation-direction` | [css_animation.dart:188](webf/lib/src/css/css_animation.dart#L188) | Hardens against `StateError` on unrecognised direction strings. |
| Replace `assert(false)` for unknown at-rules with logger warning | [rule_set.dart:110](webf/lib/src/css/rule_set.dart#L110) | `@counter-style`, `@property`, `@scope`, etc. no longer abort debug builds. |
| Treat `@supports` as always-true and parse contents inline | [parser.dart:642](webf/lib/src/css/parser/parser.dart#L642) | Every modern CSS framework's progressive-enhancement layer renders for free. |

### Phase 1 — Interaction smoothness
| Change | File | Effect |
|---|---|---|
| Per-frame flush loop now skips when no UI commands are pending and stops scheduling vsync on idle ticks | [view_controller.dart:174-194](webf/lib/src/launcher/view_controller.dart#L174) | Eliminates the constant `PostToDartSync` round-trip + forced frame schedule when the page is idle. |
| Sync fast-path in event dispatch (capture, bubble, post-handlers) — only suspend when a handler actually returns a `Future` | [event_target.dart:185-249](webf/lib/src/dom/event_target.dart#L185) | Removes one microtask hop per node × per handler in deep DOM trees. |
| Drop `Future.microtask(...)` wrap in `_dispatchEventToNative` | [binding_bridge.dart:148](webf/lib/src/bridge/binding_bridge.dart#L148) | Saves an extra scheduler hop on every event delivery. |

**Deferred** (left untouched, see roadmap below):
- 1.4 layout-read cache (needs C++ work and frame-validity invariants)
- 1.5 dedup of click hit-test (correctness risk for nested DOM)
- 1.6 pseudo-state already scoped to dirty set; existing code is correct.

### Phase 2 — CSS compatibility
| Change | File | Effect |
|---|---|---|
| `min(a, b, …)` and `max(a, b, …)` math functions | [calc.dart:25-87](webf/lib/src/css/values/calc.dart#L25) | Tailwind, Bootstrap, MUI responsive sizing now resolves instead of collapsing to 0. |
| `transformMatrix` falls back to identity on non-finite values | [transform.dart:130-200](webf/lib/src/css/transform.dart#L130) | `NaN/Inf` from `calc` divide-by-zero or unresolved percentages no longer crash Skia in release. |
| `@media`: `orientation`, `hover`, `pointer`, `prefers-reduced-motion` evaluated against platform | [css_rule.dart:478-512](webf/lib/src/css/css_rule.dart#L478) | Mobile/desktop responsive rules no longer match unconditionally. |

### Phase 3 — Bridge correctness & ergonomics
| Change | File | Effect |
|---|---|---|
| Free `dart_method_name` on async binding calls | [binding_object.dart:521](webf/lib/src/bridge/binding_object.dart#L521) | Closes a per-call leak of one `Pointer<NativeValue>`. |
| Re-load `binding_target_` after `disposed_` check (Wrapper + JS-thread lambda) | [binding_object.cc:87-133](bridge/core/binding_object.cc#L87) | Closes the use-after-free TOCTOU race when the Dart-side GC finalises a binding mid-call. |
| `PostToDartSync` timeout 2 s → 5 s + `timed_out_` flag | [task.h:85-101](bridge/multiple_threading/task.h#L85) | Avoids spurious `std::future_error` on slow Dart frames; callers can now branch on the timeout. |
| **NEW** `WebFReactiveBridge` — Stream / ValueListenable bridge | [reactive_channel.dart](webf/lib/src/module/reactive_channel.dart), [reactive_channel.js](webf/lib/src/module/reactive_channel.js) | Replaces 20-line MethodChannel boilerplate with `controller.expose('counter', myNotifier)` / `webf.reactive.observe('counter').subscribe(fn)`. |

## Using the new reactive bridge

### Dart side
```dart
final counter = ValueNotifier<int>(0);
final reactive = WebFReactiveBridge(controller);
reactive.expose('counter', counter);             // 2-way (counter is a ValueNotifier)

// Observe JS-side state:
reactive.observe<String>('userInput').listen(print);

// Or one-shot:
final user = await reactive.read<Map>('userInfo');
reactive.write('selectedTab', 'home');
```

### JS side (load `reactive_channel.js` in your page once)
```js
// Read Dart state:
const v = await webf.reactive.get('counter');

// Subscribe:
const unsub = webf.reactive.observe('counter').subscribe(v => render(v));

// Write back:
webf.reactive.set('counter', v + 1);

// Expose JS state to Dart:
webf.reactive.expose('userInput', () => store.input, v => store.input = v);
webf.reactive.push('userInput', store.input);   // emit a change
```

React/Vue integration is straightforward — wrap `observe(...).subscribe` in
`useEffect` / `onMounted`.

## Repo size before/after
- Working tree: **22 GB → 12 GB** (debug-symbols deleted)
- Pub package: trimmed via `.pubignore`
- Git history still contains the 11 GB of debug symbols; if you want to publish
  this branch as the new origin, run a one-time history rewrite:
  ```
  git filter-repo --path debug-symbols --invert-paths
  ```

### Phase 6 — Pseudo-elements & layout-read cache

| Change | File | Effect |
|---|---|---|
| `::placeholder` and `::selection` parser/matcher | [parser.dart](webf/lib/src/css/parser/parser.dart#L67), [selector.dart](webf/lib/src/css/parser/selector.dart#L36), [rule_set.dart](webf/lib/src/css/rule_set.dart#L298), [style_declaration.dart](webf/lib/src/css/style_declaration.dart) | Both legacy `:placeholder` and modern `::placeholder` syntax now parse and match. Mask bits 4 & 5. |
| `::placeholder` styling on `<input>` / `<textarea>` | [base_input.dart](webf/lib/src/html/form/base_input.dart) | `_buildHintStyle` reads `pseudoPlaceholderStyle` and feeds `color`, `font-size`, `font-weight`, `font-family` into `InputDecoration.hintStyle`. Tailwind `placeholder:text-gray-400 placeholder:italic` works. |
| `::selection` background on inputs | [base_input.dart](webf/lib/src/html/form/base_input.dart) | When the page declares `::selection { background: … }`, the input is wrapped in `TextSelectionTheme(selectionColor: …)`. |
| **Layout-read cache** (the React reconciliation perf win) | [executing_context.h](bridge/core/executing_context.h), [ui_command_buffer.cc](bridge/foundation/ui_command_buffer.cc), [binding_object.h](bridge/core/binding_object.h), [binding_object.cc](bridge/core/binding_object.cc) | `offsetWidth`/`offsetHeight`/`clientWidth`/`clientHeight` are cached per element and short-circuit `PostToDartSync` while no layout-affecting UI command has queued since the last fetch. React's measurement phase typically reads these properties N times per node per render — now N–1 of those reads stay on the JS thread. |

The layout cache uses an atomic `layout_mutation_epoch_` on `ExecutingContext`,
bumped from `UICommandBuffer::updateFlags` whenever a `kNodeMutation`,
`kStyleUpdate`, `kAttributeUpdate`, or `kNodeCreation` command is queued. A
pre/post-call epoch comparison around the `InvokeBindingMethod` ensures we
never cache a value that became stale during the round-trip.

Limitations:
- `::selection { color: … }` (foreground colour for selected text) is **not**
  applied — Flutter's `TextField` exposes no per-character selected-text
  style without subclassing `EditableText`. Background works, foreground
  silently no-ops.
- Layout cache covers only the four scalar properties for now.
  `getBoundingClientRect` / `getClientRects` / `scrollWidth` / `scrollHeight`
  still cross the bridge each call. Adding them is the next phase.
- `@container` (CSS Containment Module L3 — Tailwind `@container`) is **not**
  yet implemented. Realistic v1 estimate is ~5 hours of focused work
  (token, parser, `CSSContainerRule`, ancestor walk in
  `element_rule_collector`, re-eval trigger in `RenderBoxModel.didLayout`).
  See `docs/CSS_CASCADE_LAYERS_PLAN.md` for the related cascade-layers prior
  art.

### Phase 5 — Tailwind & animation polish

After analysing what Tailwind v3+ actually emits, these were the real gaps. The
animation pipeline itself is already healthy: `AnimationTimeline._onTick` runs
on Flutter's vsync `Ticker` and writes interpolated values straight into
`CSSRenderStyle` with **zero bridge crossings per tick**. Multi-layer
transitions, multi-layer box-shadows, linear/radial/conic gradients (including
Tailwind's `from-/to-` `var(--tw-gradient-stops)` pattern), `rgb(var(--c) /
var(--a))` slash syntax, `transform-origin`, and `aspect-ratio` are already
wired. What was missing:

| Change | File | Effect |
|---|---|---|
| `backdrop-filter` property + `BackdropFilterLayer` paint wrapper | [filter.dart](webf/lib/src/css/filter.dart#L490), [render_style.dart](webf/lib/src/css/render_style.dart#L300), [box_model.dart](webf/lib/src/rendering/box_model.dart#L1573) | Tailwind `backdrop-blur-*` / `backdrop-brightness-*` etc. now produce real blur on the parent's pixels behind the box. |
| `animationiteration` DOM event fired on each iteration boundary | [animation.dart](webf/lib/src/css/animation.dart#L244), [css_animation.dart](webf/lib/src/css/css_animation.dart#L215) | Tailwind `animate-bounce`, `animate-ping` etc. and any JS step counters now observe each cycle. |

What is intentionally **not** changed in this branch (test on a real device
and ship a follow-up):

- `scroll-behavior: smooth` for programmatic scrolls — needs hooking into the
  native ScrollController's `animateTo` path.
- `overscroll-behavior: contain / none` — needs a `ScrollPhysics` swap.
- `aspect-ratio` when both axes are auto inside an indefinite container — the
  layout pass currently only resolves the ratio when one axis is definite.
- `transform-box: fill-box` for SVG rotations.

## Phase 4 — Recommended next steps (not yet implemented)

These need device profiling to validate; treat the list as a checklist:

1. **Pre-warm**: spawn the JS isolate at app start instead of on first WebF
   widget mount. Saves ~200–400 ms first-paint on cold launches.
2. **Layout-read cache** (deferred Phase 1.4): cache `getBoundingClientRect`,
   `offsetWidth`, `offsetHeight` per element per frame. Invalidate on DOM
   mutation. Implemented in C++ near `BindingObject::InvokeBindingMethod` so JS
   readers don't roundtrip through `PostToDartSync`. Estimated 60–90 % drop in
   sync FFI calls during React reconciliation.
3. **Click hit-test dedup**: cache the result of the `PointerDown` hit-test on
   the gesture dispatcher and reuse it for the click event. Skip the second
   `boxHitTestResult` walk when the cached path is still valid. Validate
   correctness against deep DOM trees first.
4. **Benchmark suite**: add `scripts/run_benchmark.js` cases for
   `tap-to-paint`, `scroll-FPS`, `first-paint`. Wire into CI so regressions
   are caught.
5. **C++ rebuild required for Phase 3.1 / 3.2 / 3.4** to take effect at
   runtime: `npm run build:bridge:macos` (or your platform's equivalent).

## Branch hygiene

```
git remote -v
# openwebf-upstream  https://github.com/openwebf/webf.git (fetch/push)

# When ready to publish:
git remote add origin <your-fork-url>
git push -u origin webf-optimized
```

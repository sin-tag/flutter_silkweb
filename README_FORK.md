# flutter_silkweb

Optimized fork of [openwebf/webf](https://github.com/openwebf/webf) — embed
React/Vue/Tailwind apps inside Flutter with smoother animations, faster
React reconciliation, and a typed reactive bridge between Dart and JS.

## What's different from upstream `webf`

- **Layout-read cache** — `offsetWidth/Height/clientWidth/Height` are cached
  per element while no DOM mutation has happened, eliminating one
  `PostToDartSync` round-trip per React reconciliation read.
- **Idle frame loop** no longer wakes the JS thread or forces vsync when
  there are no pending UI commands.
- **Sync fast-path event dispatch** — DOM events skip a microtask hop per
  handler when the listener is synchronous.
- **CSS gaps closed for Tailwind**:
  - `min()`/`max()` calc functions
  - `backdrop-filter` (Tailwind `backdrop-blur-*`/`backdrop-brightness-*`)
  - `::placeholder` and `::selection` styling
  - `animationiteration` event (Tailwind `animate-bounce`/`animate-ping`
    step counters)
  - `@supports` parsed and inlined (progressive enhancement)
  - Multi-feature `@media`: `orientation`, `hover`, `pointer`,
    `prefers-reduced-motion`
  - Crash hardening: animation/transition null-unwraps, non-finite transform
    matrix, unknown at-rules
- **Bridge fixes**: closes `dart_method_name` leak, plugs use-after-dispose
  race in `binding_object.cc`, surfaces a 5 s `PostToDartSync` timeout flag
  instead of silently swallowing `std::future_error`.
- **`WebFReactiveBridge`** — typed Stream / `ValueListenable` bridge
  replacing 20-line MethodChannel boilerplate. JS side ships as a small
  polyfill (`reactive_channel.js`) you can `<script>` into your page.

See [OPTIMIZATION_NOTES.md](OPTIMIZATION_NOTES.md) for the full change log
with file:line references.

## Install

`flutter_silkweb` is published as a git package — no pub.dev account
required. In your app's `pubspec.yaml`:

```yaml
dependencies:
  flutter_silkweb:
    git:
      url: https://github.com/sin-tag/flutter_silkweb.git
      ref: webf-optimized
      path: webf
```

Then:

```bash
flutter pub get
# iOS only:
cd ios && pod install
```

The C++ bridge is compiled from source per platform on first build, so the
initial build is slower than a normal package. Subsequent builds reuse the
cached `.dylib`/`.so`.

## Usage

The Dart API matches upstream `webf` — only the package name changed:

```dart
import 'package:flutter_silkweb/webf.dart';

WebFController controller = WebFController(
  context,
  bundle: WebFBundle.fromUrl('https://example.com'),
);
```

### Reactive bridge (new)

```dart
final counter = ValueNotifier<int>(0);
final reactive = WebFReactiveBridge(controller);
reactive.expose('counter', counter);          // 2-way
reactive.observe<String>('userInput').listen(print);
```

```js
// after loading reactive_channel.js
const v = await webf.reactive.get('counter');
webf.reactive.observe('counter').subscribe(v => store.counter = v);
webf.reactive.set('counter', v + 1);
```

## Pinning

For production stability, pin to a specific commit instead of a branch:

```yaml
ref: 4dec6e86a   # or any newer SHA from the webf-optimized branch
```

## License

GPL-3.0-only, same as upstream. **Note**: GPL is contagious — apps that
depend on this package must also be GPL or otherwise comply with the
license. If your app is closed-source, you cannot use this package.

## Credits

This is a fork of [openwebf/webf](https://github.com/openwebf/webf).
The original engine, Dart bindings, and bridge are the work of the
OpenWebF / Kraken authors. This fork only adds the optimisations listed
above; everything else is unchanged.

## Limitations

- `@container` queries not yet implemented (next phase).
- `getBoundingClientRect` / `getClientRects` not yet cached (only the four
  scalar properties).
- `::selection { color }` foreground colour not applied — Flutter `TextField`
  exposes no per-character selected-text style hook.
- `aspect-ratio` doesn't resolve when both axes are auto inside an
  indefinite container.
- No benchmarks have been measured on real devices yet — claims are based
  on architectural analysis, not profiling. Please file issues with
  before/after frame timings if you measure regressions.

<h1 align="center">flutter_silkweb</h1>

<p align="center">
  <b>Embed React, Vue, and Tailwind apps inside Flutter — at native speed.</b>
</p>

<p align="center">
  <a href="#install"><b>Install</b></a>
  ·
  <a href="#quick-start"><b>Quick start</b></a>
  ·
  <a href="#mini-app-permissions"><b>Permissions</b></a>
  ·
  <a href="#reactive-bridge"><b>Reactive bridge</b></a>
  ·
  <a href="OPTIMIZATION_NOTES.md"><b>What's optimized</b></a>
</p>

---

`flutter_silkweb` is a W3C-compliant web rendering engine for Flutter. Drop a
React/Vue/Vite bundle into a Flutter app and it renders directly on Skia —
no WebView, no JS bridge round-trip per paint, no compromised animations.

It's designed for **mini-app workloads** where you want web-team velocity
inside a native shell: Tailwind components for UI, Flutter for camera /
sensors / payments, and a typed Dart ↔ JS reactive channel between them.

## Why

| | InAppWebView | webview_flutter | **flutter_silkweb** |
|---|---|---|---|
| Renders on | OS WebView | OS WebView | **Skia (Flutter native)** |
| Touch latency | OS-dependent | OS-dependent | **vsync-aligned, no IPC** |
| Animations | OS browser FPS | OS browser FPS | **60 fps GPU-driven** |
| Tailwind support | Full | Full | **Full** (incl. backdrop-filter, animate-bounce, ::placeholder, min/max calc) |
| Reactive state bridge | Hand-rolled `postMessage` | Hand-rolled `postMessage` | **Typed `Stream<T>` / `ValueListenable<T>`** |
| Permission gate | App-wide WebView | App-wide WebView | **Per-bundle manifest + runtime policy** |
| Bundle size | OS-bundled | OS-bundled | **~150 MB source, ~5 MB compiled bridge** |

## Install

`flutter_silkweb` ships as a git package — no pub.dev account required.

```yaml
dependencies:
  flutter_silkweb:
    git:
      url: https://github.com/sin-tag/flutter_silkweb.git
      ref: main           # or pin a specific commit / tag
      path: webf
```

Then:

```bash
flutter pub get
cd ios && pod install     # iOS only
flutter run
```

The C++ bridge is compiled from source on first build per platform. Initial
build is slower than a stock pub.dev package; subsequent builds are cached.

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:flutter_silkweb/flutter_silkweb.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: WebF(
        bundle: WebFBundle.fromUrl('https://your-react-app.com/'),
        viewportWidth: MediaQuery.of(context).size.width,
        viewportHeight: MediaQuery.of(context).size.height,
      ),
    );
  }
}
```

That's it. Your existing React / Vue / Vite output runs unmodified — no
inline-style rewrites, no Tailwind escape hatches.

## Mini-app permissions

Sandbox what a JS bundle can do at runtime. Three layers, checked in order:

1. **Static allowlist** — grants the manifest declared
2. **Static denylist** — host hard-blocks regardless of the resolver
3. **Async resolver** — prompt the user, hit your auth server, etc.

```dart
final controller = WebFController(
  context,
  bundle: WebFBundle.fromUrl('https://untrusted-app.com/'),
  permissionPolicy: WebFPermissionPolicy(
    granted: { WebFPermission.network },     // baseline trust
    denied:  { WebFPermission.fileSystem },  // hard block
    onRequest: (perm) async {
      // Show a dialog, query the OS, whatever.
      return await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Allow ${perm.id}?'),
          actions: [
            TextButton(child: Text('Deny'),  onPressed: () => Navigator.pop(_, false)),
            TextButton(child: Text('Allow'), onPressed: () => Navigator.pop(_, true)),
          ],
        ),
      ) ?? false;
    },
  ),
);
```

### Manifest-driven (recommended for distributed mini-apps)

Each bundle ships a `manifest.json`:

```json
{
  "name": "Photo Editor",
  "version": "1.2.0",
  "entry": "/index.html",
  "permissions": ["camera", "clipboard:read", "clipboard:write", "network"]
}
```

Host parses and uses it as the policy:

```dart
final manifest = WebFManifest.fromJson(await rootBundle.loadString('manifest.json'));
final policy = manifest.buildPolicy(
  alsoDeny: { WebFPermission.fileSystem },          // override regardless
  onRequest: (perm) async => await promptUser(perm), // for anything not in manifest
);
final controller = WebFController(context, bundle: ..., permissionPolicy: policy);
```

### Available permissions

| Permission | Manifest id | Gates |
|---|---|---|
| `network` | `network` | `fetch`, `XHR`, `EventSource`, `WebSocket` |
| `clipboardRead` | `clipboard:read` | `navigator.clipboard.readText()` |
| `clipboardWrite` | `clipboard:write` | `navigator.clipboard.writeText()` |
| `geolocation` | `geolocation` | `navigator.geolocation.*` |
| `camera` | `camera` | `getUserMedia({video})`, `<webf-camera>` |
| `microphone` | `microphone` | `getUserMedia({audio})` |
| `notifications` | `notifications` | `Notification`, push channel |
| `storage` | `storage` | `localStorage`, `sessionStorage`, IndexedDB |
| `fileSystem` | `file-system` | File picker / FS modules |
| `hostState` | `host-state` | `WebFReactiveBridge` writes |
| `hardwareAccess` | `hardware-access` | Bluetooth, NFC, USB plugins |
| `deviceInfo` | `device-info` | UA hints, sensors |
| `systemControl` | `system-control` | `vibrate`, `wakeLock`, etc. |

When a JS call hits a denied permission, it surfaces as a
`NotAllowedError` — the same shape browsers throw, so existing
`try { ... } catch (NotAllowedError e)` paths in your React/Vue code work
unchanged.

## Reactive bridge

Forget hand-rolling `postMessage`. Two-way typed state in two lines:

### Dart side

```dart
final counter = ValueNotifier<int>(0);
final reactive = WebFReactiveBridge(controller);
reactive.expose('counter', counter);                    // Dart → JS
reactive.observe<String>('userInput').listen(print);    // JS → Dart
```

### JS side (after loading `reactive_channel.js`)

```js
// Read Dart-side state
const v = await webf.reactive.get('counter');

// Subscribe to changes
const unsub = webf.reactive.observe('counter').subscribe(v => {
  setCounter(v);   // works in any framework
});

// Push to Dart
webf.reactive.set('counter', v + 1);

// Expose JS state to Dart
webf.reactive.expose('userInput', () => store.input, v => store.input = v);
```

Works directly with React `useEffect`, Vue `onMounted`, Solid `createEffect`.
No serialization wrappers, no `JSON.stringify` boilerplate.

## What we improved over the prior art

`flutter_silkweb` started as a fork of [openwebf/webf](https://github.com/openwebf/webf)
— huge respect to that team for the rendering engine and Dart bindings. We
focused on production-grade smoothness and the developer experience around
embedding modern frontend stacks.

Highlights:

- **Layout-read cache** — `offsetWidth/Height` etc. cached per element while
  no DOM mutation has happened, so React's measurement phase no longer blocks
  the JS thread N times per render.
- **Idle frame loop** doesn't wake the JS thread or force vsync when nothing
  is pending.
- **Sync fast-path event dispatch** — DOM events skip a microtask hop per
  handler when the listener is synchronous.
- **CSS gaps closed for Tailwind**: `min()`/`max()` calc, `backdrop-filter`,
  `::placeholder` + `::selection`, `animationiteration` event, full
  `@supports`, expanded `@media` (orientation/hover/pointer/reduced-motion).
- **Crash hardening** — null-unwraps in animation/transition timing, NaN/Inf
  transform matrices, unknown at-rules.
- **Bridge correctness** — closes a `dart_method_name` leak, plugs a
  use-after-dispose race in C++, surfaces sync timeouts instead of swallowing
  `std::future_error`.
- **Permission system** (this page) — sandbox untrusted bundles.
- **Reactive bridge** (this page) — typed Stream / `ValueListenable` over
  the existing MethodChannel.

Full file:line change log: [OPTIMIZATION_NOTES.md](OPTIMIZATION_NOTES.md).

## Status & limitations

- ✅ React (incl. measurement-heavy reconciliation), Vue 3, Solid, vanilla.
- ✅ Tailwind CSS v3.x (utilities + custom properties).
- ✅ Touch / mouse / keyboard, async event handlers.
- ✅ CSS animations, transitions, transforms (including 3D).
- ⚠️ `@container` (container queries) not yet implemented — next phase.
- ⚠️ `getBoundingClientRect` / `getClientRects` not yet in the layout cache.
- ⚠️ `::selection { color }` foreground colour cannot be applied (Flutter
  TextField has no per-character selected-text style hook).
- ⚠️ `aspect-ratio` doesn't resolve when both axes are `auto` inside an
  indefinite container.
- ⚠️ No real-device benchmarks merged yet — claims are based on
  architectural analysis. Please file issues with before/after frame
  timings.

## Versioning

Pin to a SHA in production:

```yaml
flutter_silkweb:
  git:
    url: https://github.com/sin-tag/flutter_silkweb.git
    ref: <commit-sha>
    path: webf
```

Or to a tag once we cut releases:

```yaml
ref: v0.1.0
```

## License

[GPL-3.0-only](LICENSE), inherited from the upstream engine. **GPL is
contagious** — apps that depend on `flutter_silkweb` must comply with GPL
themselves. If your app is closed-source, contact the upstream for a
commercial / Enterprise license.

## Credits

- The DOM/CSS engine, Dart bindings, and C++ bridge come from
  [openwebf/webf](https://github.com/openwebf/webf) and earlier
  [Kraken](https://github.com/openkraken/kraken). This fork only adds the
  optimisations and APIs listed above.
- QuickJS for the embedded JS runtime.
- Flutter, Skia, Dart team for the underlying platform.

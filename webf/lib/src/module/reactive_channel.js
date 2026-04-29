/*
 * WebF Reactive Bridge — JS polyfill.
 *
 * Pair of WebFReactiveBridge (Dart). Load this file once in your page before
 * any reactive usage:
 *   <script src="webf-reactive.js"></script>
 *
 * API (window.webf.reactive):
 *   observe(key) → returns an EventTarget-like { subscribe(fn) → unsub }
 *   get(key) → Promise<T>          read Dart-side state once
 *   set(key, value) → Promise<void> write Dart-side state once
 *   expose(key, getter, setter?)   make JS state visible to Dart
 *   push(key, value)               one-shot push to Dart subscribers
 *
 * Designed to be tiny (no deps, no build step). Works with React/Vue/Solid:
 *   useEffect(() => webf.reactive.observe('counter').subscribe(setCounter), []);
 */
(function (global) {
  if (!global.webf || !global.webf.methodChannel) {
    console.error('[webf-reactive] webf.methodChannel is not available; load this script after WebF is ready.');
    return;
  }
  if (global.webf.reactive) return; // already installed

  const channel = global.webf.methodChannel;
  const subscribers = new Map();           // key → Set<fn>
  const exposed = new Map();               // key → { getter, setter }

  function dispatch(key, value) {
    const set = subscribers.get(key);
    if (!set) return;
    for (const fn of set) {
      try { fn(value); } catch (e) { console.error('[webf-reactive] subscriber threw', e); }
    }
  }

  // The host MethodChannel routes every Dart→JS call here. We hook into it
  // additively so any pre-existing handler still fires for unrelated methods.
  const previousHandler = channel.setMethodCallHandler ? null : channel.onmethodcall;
  channel.setMethodCallHandler && channel.setMethodCallHandler(function (method, args) {
    args = args || [];
    switch (method) {
      case 'webf:reactive.update':
        dispatch(args[0], args[1]);
        return undefined;
      case 'webf:reactive.get': {
        const e = exposed.get(args[0]);
        return e ? e.getter() : undefined;
      }
      case 'webf:reactive.set': {
        const e = exposed.get(args[0]);
        if (e && e.setter) e.setter(args[1]);
        return undefined;
      }
      case 'webf:reactive.observe':
        // Dart asked us to start sending updates for this key.
        // No-op; we always emit on expose() / push().
        return undefined;
      case 'webf:reactive.unobserve':
        return undefined;
      default:
        return previousHandler ? previousHandler(method, args) : undefined;
    }
  });

  function observe(key) {
    return {
      subscribe(fn) {
        let set = subscribers.get(key);
        if (!set) { set = new Set(); subscribers.set(key, set); }
        set.add(fn);
        // Pull once on subscribe so the consumer doesn't have to wait for the
        // next change.
        channel.invokeMethod('webf:reactive.get', [key]).then(function (v) {
          if (v !== undefined) fn(v);
        });
        return function unsubscribe() {
          const s = subscribers.get(key);
          if (!s) return;
          s.delete(fn);
          if (s.size === 0) subscribers.delete(key);
        };
      }
    };
  }

  function get(key) {
    return channel.invokeMethod('webf:reactive.get', [key]);
  }

  function set(key, value) {
    return channel.invokeMethod('webf:reactive.set', [key, value]);
  }

  function expose(key, getter, setter) {
    exposed.set(key, { getter: getter, setter: setter });
  }

  function push(key, value) {
    channel.invokeMethod('webf:reactive.update', [key, value]);
  }

  global.webf.reactive = { observe: observe, get: get, set: set, expose: expose, push: push };
})(typeof window !== 'undefined' ? window : globalThis);

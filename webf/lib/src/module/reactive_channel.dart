/*
 * Copyright (C) 2024-present The OpenWebF Company. All rights reserved.
 * Licensed under GNU GPL with Enterprise exception.
 */

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_silkweb/launcher.dart';
import 'package:flutter_silkweb/module.dart';

/// Two-way reactive bridge between Dart and JS state.
///
/// WebF's stock MethodChannel is fully imperative: every value transfer needs
/// a matching invokeMethod / methodCallHandler pair. This wrapper turns that
/// into a typed pub/sub built on top of [ValueListenable] and [Stream], so
/// React/Vue components can `subscribe(key)` on a value the host app stores
/// in a [ValueNotifier] and have changes delivered automatically — and vice
/// versa.
///
/// Wire format (over the existing MethodChannel):
///   webf:reactive.update  [key, value]   JS or Dart pushes a new value
///   webf:reactive.get     [key]          synchronous read of remote state
///   webf:reactive.set     [key, value]   write into remote state
///   webf:reactive.observe [key]          subscribe (idempotent)
///   webf:reactive.unobserve [key]        cancel subscription
///
/// JS counterpart polyfill ships with the package; load it once in the page
/// before any reactive usage.
class WebFReactiveBridge {
  WebFReactiveBridge(this._controller) {
    _wireJsMethodCalls();
  }

  final WebFController _controller;
  final Map<String, _ExposedState> _exposed = {};
  final Map<String, StreamController<dynamic>> _observers = {};
  MethodCallCallback? _previousCallback;

  /// Expose a [ValueListenable] (e.g. [ValueNotifier]) so JS subscribers see
  /// every change. If the listenable is also a [ValueNotifier], JS may write
  /// back via `webf.reactive.set(key, value)`.
  void expose<T>(String key, ValueListenable<T> listenable) {
    _exposed[key]?.detach();
    void listener() => _emitChange(key, listenable.value);
    listenable.addListener(listener);

    void Function(dynamic)? setter;
    if (listenable is ValueNotifier<T>) {
      setter = (dynamic v) {
        try {
          listenable.value = v as T;
        } catch (_) {
          // Type mismatch from JS — ignore rather than throwing across the bridge.
        }
      };
    }

    _exposed[key] = _ExposedState(
      () => listenable.value,
      setter,
      () => listenable.removeListener(listener),
    );
    // Send the initial value so newly subscribed JS code can paint immediately.
    _emitChange(key, listenable.value);
  }

  /// Stop exposing [key].
  void unexpose(String key) {
    _exposed.remove(key)?.detach();
  }

  /// Push a one-off value to any JS subscribers under [key]. Useful when the
  /// source isn't a [ValueListenable].
  void push(String key, dynamic value) => _emitChange(key, value);

  /// Subscribe to JS-side state. The first call also asks JS to start
  /// emitting; subsequent calls share the same broadcast stream.
  Stream<T> observe<T>(String key) {
    final controller = _observers.putIfAbsent(
      key,
      () => StreamController<dynamic>.broadcast(
        onCancel: () {
          _observers.remove(key);
          _controller.javascriptChannel.invokeMethod('webf:reactive.unobserve', [key]);
        },
      ),
    );
    _controller.javascriptChannel.invokeMethod('webf:reactive.observe', [key]);
    return controller.stream.cast<T>();
  }

  /// One-shot read of a JS-side value.
  Future<T?> read<T>(String key) async {
    final result = await _controller.javascriptChannel.invokeMethod('webf:reactive.get', [key]);
    return result is T ? result : null;
  }

  /// One-shot write into JS-side state.
  Future<void> write(String key, dynamic value) async {
    await _controller.javascriptChannel.invokeMethod('webf:reactive.set', [key, value]);
  }

  void _wireJsMethodCalls() {
    final channel = _controller.javascriptChannel;
    _previousCallback = channel.methodCallCallback;
    channel.onMethodCall = _handleJsCall;
  }

  Future<dynamic> _handleJsCall(String method, dynamic args) async {
    final List list = args is List ? args : const [];
    switch (method) {
      case 'webf:reactive.get':
        return list.isNotEmpty ? _exposed[list[0] as String]?.getter() : null;
      case 'webf:reactive.set':
        if (list.length >= 2) {
          _exposed[list[0] as String]?.setter?.call(list[1]);
        }
        return null;
      case 'webf:reactive.update':
        if (list.length >= 2) {
          _observers[list[0] as String]?.add(list[1]);
        }
        return null;
      case 'webf:reactive.snapshot':
        // JS asked for the full set of currently-exposed keys + values.
        return _exposed
            .map((k, v) => MapEntry(k, v.getter()));
      default:
        // Anything not in our reactive namespace falls through to whatever
        // handler the host app installed first.
        return _previousCallback?.call(method, args);
    }
  }

  void _emitChange(String key, dynamic value) {
    _controller.javascriptChannel.invokeMethod('webf:reactive.update', [key, value]);
  }

  /// Tear down all subscriptions. Safe to call multiple times.
  void dispose() {
    for (final state in _exposed.values) {
      state.detach();
    }
    _exposed.clear();
    for (final controller in _observers.values) {
      controller.close();
    }
    _observers.clear();
  }
}

class _ExposedState {
  _ExposedState(this.getter, this.setter, this.detach);

  final dynamic Function() getter;
  final void Function(dynamic)? setter;
  final void Function() detach;
}

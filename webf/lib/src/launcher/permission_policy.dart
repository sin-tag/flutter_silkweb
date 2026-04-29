/*
 * Copyright (C) 2024-present The OpenWebF Company. All rights reserved.
 * Licensed under GNU GPL with Enterprise exception.
 */

import 'dart:async';
import 'dart:convert';

/// Capabilities a flutter_silkweb mini-app can request from its host. Each
/// capability gates one or more JS APIs / native modules: if a permission is
/// not granted (and no resolver upgrades it on demand), the corresponding
/// JS call throws `NotAllowedError`.
///
/// Add new entries in lockstep with the module that consumes them. The string
/// name is what shows up in `manifest.json` and what the JS-side
/// `webf.permissions.query()` API uses.
enum WebFPermission {
  /// `fetch()`, `XMLHttpRequest`, `EventSource`, `WebSocket`. Default policy
  /// grants this; revoke when sandboxing untrusted bundles.
  network('network'),

  /// `navigator.clipboard.readText()` / `Clipboard` module read.
  clipboardRead('clipboard:read'),

  /// `navigator.clipboard.writeText()` / `Clipboard` module write.
  clipboardWrite('clipboard:write'),

  /// `navigator.geolocation.getCurrentPosition()`.
  geolocation('geolocation'),

  /// `navigator.mediaDevices.getUserMedia({video})` and `<webf-camera>`.
  camera('camera'),

  /// `navigator.mediaDevices.getUserMedia({audio})`.
  microphone('microphone'),

  /// `Notification` + push notification module.
  notifications('notifications'),

  /// `localStorage`, `sessionStorage`, IndexedDB-style modules.
  storage('storage'),

  /// File picker / file system access modules.
  fileSystem('file-system'),

  /// `WebFController.expose` / `WebFReactiveBridge` write into host state.
  hostState('host-state'),

  /// Bluetooth, NFC, USB-style hardware access (extension modules).
  hardwareAccess('hardware-access'),

  /// `webf.deviceInfo`, `navigator.userAgentData`, sensor APIs.
  deviceInfo('device-info'),

  /// `vibrate`, `wakeLock`, etc.
  systemControl('system-control');

  const WebFPermission(this.id);

  /// Stable identifier used in `manifest.json` and the JS bridge.
  final String id;

  static WebFPermission? fromId(String id) {
    for (final p in WebFPermission.values) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// Result of a permission lookup. Mirrors the W3C Permissions API states so
/// JS code can pretend it's running in a real browser.
enum WebFPermissionStatus { granted, denied, prompt }

/// Decides whether a mini-app may access a permission-gated capability.
///
/// Three layers, checked in order:
///
/// 1. **Static allowlist** ([granted]) — fastest. Set this from the host
///    Flutter app for trusted bundles, or from a parsed [WebFManifest] for
///    auto-granted permissions.
/// 2. **Static denylist** ([denied]) — short-circuits even if a resolver is
///    configured, so a host can hard-block sensitive capabilities.
/// 3. **Async resolver** ([onRequest]) — called when the permission is
///    neither granted nor denied. Show a dialog, query the OS, hit a server
///    — anything that returns a `bool`. Results may be cached if [cache] is
///    `true` (default).
///
/// ```dart
/// WebFController(
///   ...,
///   permissionPolicy: WebFPermissionPolicy(
///     granted: {WebFPermission.network},
///     denied:  {WebFPermission.fileSystem},
///     onRequest: (perm) async {
///       return await showDialog<bool>(...) ?? false;
///     },
///   ),
/// );
/// ```
class WebFPermissionPolicy {
  WebFPermissionPolicy({
    Set<WebFPermission> granted = const {},
    Set<WebFPermission> denied = const {},
    this.onRequest,
    this.cache = true,
  })  : _granted = Set.of(granted),
        _denied = Set.of(denied);

  /// Permission policy that grants nothing — every JS API gated by a
  /// permission throws unless the host opts in. Use as a starting point for
  /// untrusted bundles.
  factory WebFPermissionPolicy.deny() => WebFPermissionPolicy();

  /// Legacy / development default — grants everything except hardware access.
  /// **Do not use** for third-party bundles.
  factory WebFPermissionPolicy.trustHost() => WebFPermissionPolicy(
        granted: WebFPermission.values.toSet()..remove(WebFPermission.hardwareAccess),
      );

  final Set<WebFPermission> _granted;
  final Set<WebFPermission> _denied;
  final Future<bool> Function(WebFPermission permission)? onRequest;
  final bool cache;

  Set<WebFPermission> get grantedSnapshot => Set.unmodifiable(_granted);
  Set<WebFPermission> get deniedSnapshot => Set.unmodifiable(_denied);

  /// Synchronous query — used by JS `webf.permissions.query()`. Never
  /// invokes [onRequest]; that's [check]'s job.
  WebFPermissionStatus query(WebFPermission permission) {
    if (_denied.contains(permission)) return WebFPermissionStatus.denied;
    if (_granted.contains(permission)) return WebFPermissionStatus.granted;
    return WebFPermissionStatus.prompt;
  }

  /// Returns `true` iff the call may proceed. Triggers [onRequest] when the
  /// answer isn't already known. Idempotent: once the resolver returns, the
  /// outcome is cached as either `granted` or `denied`.
  Future<bool> check(WebFPermission permission) async {
    if (_denied.contains(permission)) return false;
    if (_granted.contains(permission)) return true;
    final resolver = onRequest;
    if (resolver == null) return false;
    final ok = await resolver(permission);
    if (cache) {
      (ok ? _granted : _denied).add(permission);
    }
    return ok;
  }

  /// Promote a permission to `granted` (e.g. after the user taps "Allow"
  /// in an OS dialog). Removes any prior denial.
  void grant(WebFPermission permission) {
    _denied.remove(permission);
    _granted.add(permission);
  }

  /// Hard-block a permission. Subsequent [check] calls return `false`
  /// without consulting the resolver.
  void deny(WebFPermission permission) {
    _granted.remove(permission);
    _denied.add(permission);
  }

  /// Drop both grant and deny so the next [check] re-prompts.
  void reset(WebFPermission permission) {
    _granted.remove(permission);
    _denied.remove(permission);
  }
}

/// Thrown from a permission-gated module when [WebFPermissionPolicy.check]
/// returns false. JS sees this as `NotAllowedError`.
class WebFPermissionDeniedError extends Error {
  WebFPermissionDeniedError(this.permission);

  final WebFPermission permission;

  @override
  String toString() =>
      'WebFPermissionDeniedError: ${permission.id} not granted by host';
}

/// Parsed `manifest.json` from a mini-app bundle. Maps permission ids to
/// [WebFPermission] entries; ignores unknown ids so older hosts don't break
/// on newer manifests.
///
/// Wire format:
///
/// ```json
/// {
///   "name": "My Mini App",
///   "version": "1.0.0",
///   "entry": "/index.html",
///   "permissions": ["network", "clipboard:read", "geolocation"],
///   "metadata": { "icon": "/icon.png" }
/// }
/// ```
class WebFManifest {
  WebFManifest({
    required this.name,
    required this.version,
    required this.entry,
    required this.permissions,
    this.metadata = const {},
  });

  final String name;
  final String version;
  final String entry;
  final Set<WebFPermission> permissions;
  final Map<String, dynamic> metadata;

  static WebFManifest fromJson(String jsonText) {
    final dynamic decoded = jsonDecode(jsonText);
    if (decoded is! Map) {
      throw FormatException('Manifest must be a JSON object');
    }
    final Set<WebFPermission> perms = <WebFPermission>{};
    final dynamic raw = decoded['permissions'];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is! String) continue;
        final p = WebFPermission.fromId(entry);
        if (p != null) perms.add(p);
      }
    }
    final dynamic meta = decoded['metadata'];
    return WebFManifest(
      name: (decoded['name'] as String?) ?? 'Untitled',
      version: (decoded['version'] as String?) ?? '0.0.0',
      entry: (decoded['entry'] as String?) ?? '/index.html',
      permissions: perms,
      metadata: meta is Map<String, dynamic> ? meta : const {},
    );
  }

  /// Build a [WebFPermissionPolicy] that auto-grants whatever the manifest
  /// declares. Wrap in your own resolver if the host should still prompt.
  WebFPermissionPolicy buildPolicy({
    Future<bool> Function(WebFPermission permission)? onRequest,
    Set<WebFPermission> alsoDeny = const {},
  }) {
    return WebFPermissionPolicy(
      granted: permissions,
      denied: alsoDeny,
      onRequest: onRequest,
    );
  }
}

/*
 * Copyright (C) 2024-present The OpenWebF Company. All rights reserved.
 * Licensed under GNU GPL with Enterprise exception.
 */

import 'dart:convert';

/// W3C [Import Maps](https://github.com/WICG/import-maps) implementation.
///
/// An import map redirects bare module specifiers (`import "react"`) to URLs,
/// and applies different rules in different scopes (path-prefixed mappings).
///
/// Wire format mirrors the spec:
/// ```html
/// <script type="importmap">
///   {
///     "imports": {
///       "react": "https://esm.sh/react@18",
///       "react-dom/": "https://esm.sh/react-dom@18/",
///       "lodash": "/vendor/lodash.js"
///     },
///     "scopes": {
///       "/legacy/": {
///         "react": "https://esm.sh/react@17"
///       }
///     }
///   }
/// </script>
/// ```
///
/// Resolution rules (browser-spec compatible):
/// 1. Walk scopes from longest path-prefix matching the importer's URL down
///    to shortest; first match wins.
/// 2. Fall through to the top-level `imports` table.
/// 3. **Trailing-slash mappings** (key + value both end with `/`) match any
///    specifier starting with that prefix and produce an address by string
///    substitution. So `"react-dom/"` mapped to `"https://esm.sh/react-dom@18/"`
///    rewrites `"react-dom/client"` → `"https://esm.sh/react-dom@18/client"`.
/// 4. Exact-match keys win over trailing-slash keys when both could apply.
class ImportMap {
  ImportMap({
    Map<String, String> imports = const {},
    Map<String, Map<String, String>> scopes = const {},
  })  : _imports = Map.unmodifiable(imports),
        _scopes = Map.unmodifiable(
          scopes.map((k, v) => MapEntry(k, Map.unmodifiable(v))),
        );

  /// Empty no-op map. Returned by [Document.importMap] until a real one is
  /// installed; safe to call [resolve] on it.
  static final ImportMap empty = ImportMap();

  final Map<String, String> _imports;
  final Map<String, Map<String, String>> _scopes;

  bool get isEmpty => _imports.isEmpty && _scopes.isEmpty;

  Map<String, String> get imports => _imports;
  Map<String, Map<String, String>> get scopes => _scopes;

  /// Parse an import-map JSON string. Invalid entries are dropped silently
  /// to mirror browser tolerance — a single bad mapping must not poison the
  /// whole map.
  static ImportMap parse(String jsonText) {
    final dynamic decoded = jsonDecode(jsonText);
    if (decoded is! Map) return empty;
    return ImportMap(
      imports: _readEntries(decoded['imports']),
      scopes: _readScopes(decoded['scopes']),
    );
  }

  static Map<String, String> _readEntries(dynamic value) {
    if (value is! Map) return const {};
    final out = <String, String>{};
    value.forEach((k, v) {
      if (k is String && v is String) out[k] = v;
    });
    return out;
  }

  static Map<String, Map<String, String>> _readScopes(dynamic value) {
    if (value is! Map) return const {};
    final out = <String, Map<String, String>>{};
    value.forEach((k, v) {
      if (k is String) out[k] = _readEntries(v);
    });
    return out;
  }

  /// Resolve [specifier] (the module URL JS asked for) given the URL of the
  /// importing module ([importerUrl], may be empty for top-level scripts).
  ///
  /// Returns the mapped URL or `null` if the specifier doesn't match any
  /// entry. The caller is responsible for falling through to default
  /// path-relative resolution.
  String? resolve(String specifier, String importerUrl) {
    // 1. Scoped mappings (longest prefix wins).
    if (_scopes.isNotEmpty) {
      final matchingScopes = _scopes.keys
          .where((scope) => importerUrl.startsWith(scope))
          .toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final scope in matchingScopes) {
        final hit = _matchEntry(_scopes[scope]!, specifier);
        if (hit != null) return hit;
      }
    }
    // 2. Top-level imports.
    return _matchEntry(_imports, specifier);
  }

  /// Exact key first, then trailing-slash prefix. `null` = no match.
  String? _matchEntry(Map<String, String> table, String specifier) {
    final exact = table[specifier];
    if (exact != null) return exact;
    String? bestPrefix;
    for (final key in table.keys) {
      if (!key.endsWith('/')) continue;
      if (!specifier.startsWith(key)) continue;
      if (bestPrefix == null || key.length > bestPrefix.length) {
        bestPrefix = key;
      }
    }
    if (bestPrefix == null) return null;
    final tail = specifier.substring(bestPrefix.length);
    return table[bestPrefix]! + tail;
  }
}

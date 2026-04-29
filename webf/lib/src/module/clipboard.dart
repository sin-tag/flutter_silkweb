/*
 * Copyright (C) 2024-present The OpenWebF Company. All rights reserved.
 * Licensed under GNU GPL with Enterprise exception.
 */
/*
 * Copyright (C) 2019-2022 The Kraken authors. All rights reserved.
 * Copyright (C) 2022-2024 The WebF authors. All rights reserved.
 */

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_silkweb/launcher.dart';
import 'package:flutter_silkweb/src/module/module_manager.dart';

class ClipBoardModule extends WebFBaseModule {
  @override
  String get name => 'Clipboard';
  ClipBoardModule(super.moduleManager);

  static Future<String> readText() async {
    ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null) return '';
    return data.text ?? '';
  }

  static Future<void> writeText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  @override
  void dispose() {}

  @override
  Future<dynamic> invoke(String method, List<dynamic> params) async {
    final controller = moduleManager?.controller;
    if (method == 'readText') {
      // Permission gate — host can revoke clipboard:read for untrusted bundles.
      if (controller != null) {
        await controller.requirePermission(WebFPermission.clipboardRead);
      }
      return await ClipBoardModule.readText();
    }
    if (method == 'writeText') {
      if (controller != null) {
        await controller.requirePermission(WebFPermission.clipboardWrite);
      }
      await ClipBoardModule.writeText(params[0]);
      return null;
    }
    return null;
  }
}

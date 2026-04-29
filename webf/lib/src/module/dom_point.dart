/*
 * Copyright (C) 2024-present The OpenWebF Company. All rights reserved.
 * Licensed under GNU GPL with Enterprise exception.
 */
import 'package:flutter_silkweb/bridge.dart';
import 'package:flutter_silkweb/module.dart';
import 'package:flutter_silkweb/src/geometry/dom_point.dart';

class DOMPointModule extends WebFBaseModule {
  DOMPointModule(super.moduleManager);

  @override
  void dispose() {
  }

  @override
  dynamic invoke(String method, List<dynamic> params) {
    if (method == 'fromPoint') {
      final firstValue = params[0];
      if (firstValue.runtimeType == DOMPoint) {
        DOMPoint domPoint = firstValue;

        return DOMPoint.fromPoint(
            BindingContext(domPoint.ownerView, domPoint.ownerView.contextId, allocateNewBindingObject()), domPoint);
      }
    }
  }

  @override
  String get name => 'DOMPoint';

}

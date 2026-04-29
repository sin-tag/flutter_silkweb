/*
 * Copyright (C) 2024-present The OpenWebF Company. All rights reserved.
 * Licensed under GNU GPL with Enterprise exception.
 */
/*
 * Copyright (C) 2023-present The WebF authors. All rights reserved.
 */
import 'package:flutter_silkweb/css.dart';
import 'package:flutter_silkweb/dom.dart';
import 'package:flutter_silkweb/bridge.dart';

const Map<String, dynamic> _defaultStyle = {
  DISPLAY: INLINE,
};

enum PseudoKind {
  kPseudoBefore,
  kPseudoAfter,
}

class PseudoElement extends Element {
  final PseudoKind kind;
  final Element parent;

  PseudoElement(this.kind, this.parent, [BindingContext? context]) : super(context) {
    tagName = 'Pseudo';
  }

  @override
  Map<String, dynamic> get defaultStyle => _defaultStyle;
}

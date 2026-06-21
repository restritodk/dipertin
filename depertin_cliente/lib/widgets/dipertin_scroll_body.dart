import 'package:flutter/material.dart';

import '../utils/safe_area_insets.dart';

/// Scroll padrão do app: respeita barra do Android, gestos e teclado.
class DiPertinScrollBody extends StatelessWidget {
  const DiPertinScrollBody({
    super.key,
    required this.child,
    this.padding,
    this.physics,
    this.controller,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.onDrag,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final ScrollController? controller;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: EdgeInsets.zero,
      child: SingleChildScrollView(
        controller: controller,
        physics: physics,
        keyboardDismissBehavior: keyboardDismissBehavior,
        padding: padding ?? diPertinScrollPaddingInner(context),
        child: child,
      ),
    );
  }
}

/// ListView com o mesmo padding seguro do [DiPertinScrollBody].
class DiPertinListBody extends StatelessWidget {
  const DiPertinListBody({
    super.key,
    required this.children,
    this.padding,
    this.physics,
    this.controller,
    this.shrinkWrap = false,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final ScrollController? controller;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: EdgeInsets.zero,
      child: ListView(
        controller: controller,
        physics: physics,
        shrinkWrap: shrinkWrap,
        padding: padding ?? diPertinScrollPaddingInner(context, top: 12),
        children: children,
      ),
    );
  }
}

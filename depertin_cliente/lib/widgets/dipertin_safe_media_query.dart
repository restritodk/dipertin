import 'dart:math' show max;

import 'package:flutter/material.dart';

import '../utils/safe_area_insets.dart';

/// Garante [MediaQuery.padding] / [MediaQuery.viewPadding] mínimos em todo o app.
///
/// Use no [MaterialApp.builder]. Telas com botão fixo inferior devem preferir
/// [DiPertinSafeBottomPanel] ou [diPertinScrollPadding].
class DiPertinSafeMediaQuery extends StatelessWidget {
  const DiPertinSafeMediaQuery({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottom = diPertinSafeAreaBottom(context);
    final top = diPertinSafeAreaTop(context);

    return MediaQuery(
      data: mq.copyWith(
        padding: mq.padding.copyWith(
          bottom: max(mq.padding.bottom, bottom),
          top: max(mq.padding.top, top),
        ),
        viewPadding: mq.viewPadding.copyWith(
          bottom: max(mq.viewPadding.bottom, bottom),
          top: max(mq.viewPadding.top, top),
        ),
      ),
      child: child,
    );
  }
}

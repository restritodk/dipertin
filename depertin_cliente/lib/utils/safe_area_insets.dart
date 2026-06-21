import 'dart:math' show max;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

/// Fallback quando o embedding não reporta inset (barra 3 botões ~48dp).
const double kAndroidNavigationBarFallback = 48.0;

/// Inset inferior seguro: gestos, botões do Android ou home indicator.
double diPertinSafeAreaBottom(BuildContext context) {
  final mq = MediaQuery.of(context);
  var bottom = max(mq.padding.bottom, mq.viewPadding.bottom);
  if (bottom < 24 &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android) {
    bottom = kAndroidNavigationBarFallback;
  }
  return bottom;
}

/// Inset superior: status bar / notch.
double diPertinSafeAreaTop(BuildContext context) {
  final mq = MediaQuery.of(context);
  return max(mq.padding.top, mq.viewPadding.top);
}

/// Conteúdo dentro do [MainNavigator] (aba Perfil/Vitrine/Buscar): barra do app + sistema.
EdgeInsets diPertinScrollPaddingTabShell(
  BuildContext context, {
  double left = 16,
  double top = 12,
  double right = 16,
  double extraBottom = 16,
}) {
  return diPertinScrollPadding(
    context,
    left: left,
    top: top,
    right: right,
    extraBottom: extraBottom + kBottomNavigationBarHeight,
  );
}

/// Padding interno quando o pai já é [SafeArea] (ex.: [DiPertinScrollBody]).
EdgeInsets diPertinScrollPaddingInner(
  BuildContext context, {
  double left = 16,
  double top = 16,
  double right = 16,
  double extraBottom = 16,
}) {
  return EdgeInsets.fromLTRB(
    left,
    top,
    right,
    extraBottom + MediaQuery.viewInsetsOf(context).bottom,
  );
}

/// Padding de scroll com área segura + teclado aberto (sem [SafeArea] no pai).
EdgeInsets diPertinScrollPadding(
  BuildContext context, {
  double left = 0,
  double top = 0,
  double right = 0,
  double extraBottom = 16,
}) {
  final mq = MediaQuery.of(context);
  return EdgeInsets.fromLTRB(
    left,
    top,
    right,
    extraBottom + diPertinSafeAreaBottom(context) + mq.viewInsets.bottom,
  );
}

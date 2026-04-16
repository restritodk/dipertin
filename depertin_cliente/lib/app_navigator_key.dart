import 'package:flutter/material.dart';

/// Navigator raiz do [MaterialApp] — usado quando o [BuildContext] da tela
/// atual deixa de existir após `pushNamedAndRemoveUntil`.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

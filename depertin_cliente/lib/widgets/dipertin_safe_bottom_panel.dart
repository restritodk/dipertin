import 'package:flutter/material.dart';

/// Painel fixo no rodapé (checkout, ações primárias) acima da barra do sistema.
class DiPertinSafeBottomPanel extends StatelessWidget {
  const DiPertinSafeBottomPanel({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 12),
    this.boxShadow = const [
      BoxShadow(
        color: Colors.black12,
        blurRadius: 10,
        offset: Offset(0, -5),
      ),
    ],
  });

  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  final List<BoxShadow> boxShadow;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: EdgeInsets.zero,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          boxShadow: boxShadow,
        ),
        child: child,
      ),
    );
  }
}

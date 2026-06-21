import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Rodapé "DiPertin vX.Y.Z" — versão lida de [PackageInfo] (espelha [pubspec.yaml]).
class DiPertinVersaoRodape extends StatefulWidget {
  const DiPertinVersaoRodape({
    super.key,
    this.textStyle,
    this.prefixo = 'DiPertin v',
  });

  final TextStyle? textStyle;
  final String prefixo;

  @override
  State<DiPertinVersaoRodape> createState() => _DiPertinVersaoRodapeState();
}

class _DiPertinVersaoRodapeState extends State<DiPertinVersaoRodape> {
  String? _versao;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      final v = info.version.trim();
      setState(() => _versao = v.isEmpty ? null : v);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final estilo = widget.textStyle ??
        TextStyle(
          color: Colors.grey.shade400,
          fontSize: 11,
        );
    final texto = _versao == null
        ? '${widget.prefixo}…'
        : '${widget.prefixo}$_versao';

    return Text(
      texto,
      textAlign: TextAlign.center,
      style: estilo,
    );
  }
}

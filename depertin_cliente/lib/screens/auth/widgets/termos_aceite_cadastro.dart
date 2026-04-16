// Arquivo: lib/screens/auth/widgets/termos_aceite_cadastro.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../comum/politicas/politica_privacidade_screen.dart';
import '../../comum/politicas/politica_uso_screen.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);

/// Versão dos documentos legais aceitos no cadastro (alinhada à data publicada no app).
class TermosCadastroFirestore {
  TermosCadastroFirestore._();

  static const String versaoDocumentos = '2026-04';

  static Map<String, dynamic> camposAceite() => {
        'aceite_termos_privacidade_em': FieldValue.serverTimestamp(),
        'aceite_termos_versao': versaoDocumentos,
      };
}

/// Checkbox + links para Termos de Uso e Política de Privacidade (cadastro).
class TermosAceiteCadastroWidget extends StatelessWidget {
  const TermosAceiteCadastroWidget({
    super.key,
    required this.aceito,
    required this.onChanged,
  });

  final bool aceito;
  final ValueChanged<bool> onChanged;

  static TextStyle _linkStyle() => const TextStyle(
        color: _diPertinRoxo,
        fontWeight: FontWeight.w700,
        decoration: TextDecoration.underline,
        fontSize: 13.5,
        height: 1.45,
      );

  static TextStyle _textoCorpo() => TextStyle(
        fontSize: 13.5,
        height: 1.45,
        color: Colors.grey.shade800,
      );

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: aceito,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: _diPertinRoxo,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 0,
            runSpacing: 4,
            children: [
              Text('Li e aceito os ', style: _textoCorpo()),
              InkWell(
                onTap: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PoliticaUsoScreen(),
                    ),
                  );
                },
                child: Text('Termos de Uso', style: _linkStyle()),
              ),
              Text(' e a ', style: _textoCorpo()),
              InkWell(
                onTap: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PoliticaPrivacidadeScreen(),
                    ),
                  );
                },
                child: Text('Política de Privacidade', style: _linkStyle()),
              ),
              Text(' para concluir meu cadastro.', style: _textoCorpo()),
            ],
          ),
        ),
      ],
    );
  }
}

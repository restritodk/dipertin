// Arquivo: lib/screens/entregador/configuracoes/configuracoes_em_construcao_screen.dart

import 'package:flutter/material.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);

class ConfiguracoesEmConstrucaoScreen extends StatelessWidget {
  final String titulo;
  final String? mensagem;

  const ConfiguracoesEmConstrucaoScreen({
    super.key,
    required this.titulo,
    this.mensagem,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          titulo,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: _roxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: _laranja.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.build_rounded,
                  size: 48,
                  color: _laranja,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Em construção',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _roxo,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                mensagem ??
                    'Este recurso será liberado em breve. Aguarde as próximas atualizações.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

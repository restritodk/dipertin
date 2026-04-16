import 'package:flutter/material.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _fundo = Color(0xFFF5F4F8);

/// Bloco de texto com título opcional (cláusulas e capítulos).
class PolicySection {
  const PolicySection({this.titulo, required this.corpo});

  final String? titulo;
  final String corpo;
}

/// Layout para documentos legais: seções com títulos em destaque, corpo justificável.
class PolicyScrollPage extends StatelessWidget {
  const PolicyScrollPage({
    super.key,
    required this.title,
    required this.sections,
    this.rodape,
  });

  final String title;
  final List<PolicySection> sections;
  final String? rodape;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 17,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: _diPertinRoxo,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8E6ED)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'DiPertin',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Última atualização: abril de 2026',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Documento jurídico disponibilizado no aplicativo. '
                'A versão vigente é a publicada nesta interface; recomenda-se '
                'a leitura integral antes da utilização dos serviços.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Colors.grey.shade700,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 20),
              for (var i = 0; i < sections.length; i++) ...[
                if (i > 0) const SizedBox(height: 18),
                if (sections[i].titulo != null) ...[
                  SelectableText(
                    sections[i].titulo!,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SelectableText(
                  sections[i].corpo,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.58,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
              if (rodape != null && rodape!.isNotEmpty) ...[
                const SizedBox(height: 24),
                SelectableText(
                  rodape!,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

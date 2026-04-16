import 'package:flutter/material.dart';

import 'politica_compra_screen.dart';
import 'politica_privacidade_screen.dart';
import 'politica_uso_screen.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoTela = Color(0xFFF5F4F8);

/// Menu: Política de uso, Política de compra, Política de privacidade.
class PoliticaMenuScreen extends StatelessWidget {
  const PoliticaMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundoTela,
      appBar: AppBar(
        title: const Text(
          'Política e privacidade',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: _diPertinRoxo,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Documentos legais',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Leia as regras de uso da plataforma, as condições de compra e '
              'como tratamos seus dados pessoais.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            _card(
              children: [
                _item(
                  context,
                  icon: Icons.gavel_outlined,
                  cor: _diPertinRoxo,
                  titulo: 'Política de uso',
                  subtitulo: 'Regras gerais da plataforma DiPertin',
                  destino: const PoliticaUsoScreen(),
                ),
                Divider(height: 1, color: Colors.grey.shade200),
                _item(
                  context,
                  icon: Icons.shopping_bag_outlined,
                  cor: _diPertinLaranja,
                  titulo: 'Política de compra',
                  subtitulo: 'Pedidos, pagamentos e entregas',
                  destino: const PoliticaCompraScreen(),
                ),
                Divider(height: 1, color: Colors.grey.shade200),
                _item(
                  context,
                  icon: Icons.privacy_tip_outlined,
                  cor: Colors.grey.shade700,
                  titulo: 'Política de privacidade',
                  subtitulo: 'Dados pessoais e segurança da informação',
                  destino: const PoliticaPrivacidadeScreen(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
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
      child: Column(children: children),
    );
  }

  Widget _item(
    BuildContext context, {
    required IconData icon,
    required Color cor,
    required String titulo,
    required String subtitulo,
    required Widget destino,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: cor, size: 22),
      ),
      title: Text(
        titulo,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: Color(0xFF1A1A2E),
        ),
      ),
      subtitle: Text(
        subtitulo,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => destino),
        );
      },
    );
  }
}

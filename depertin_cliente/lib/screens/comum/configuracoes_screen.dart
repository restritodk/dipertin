// Arquivo: lib/screens/comum/configuracoes_screen.dart

import 'package:flutter/material.dart';

import 'package:depertin_cliente/screens/cliente/meus_enderecos_screen.dart';
import 'package:depertin_cliente/screens/comum/configuracao_chat_screen.dart';
import 'package:depertin_cliente/screens/comum/configuracao_notificacoes_screen.dart';
import 'package:depertin_cliente/screens/comum/conta_exclusao_flow.dart';
import 'package:depertin_cliente/screens/comum/conta_seguranca_screen.dart';
import 'package:depertin_cliente/screens/comum/politicas/politica_menu_screen.dart';
import 'package:depertin_cliente/screens/comum/sobre_screen.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoTela = Color(0xFFF5F4F8);

/// Painel de configurações — cada item pode ganhar tela própria depois.
class ConfiguracoesScreen extends StatelessWidget {
  const ConfiguracoesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundoTela,
      appBar: AppBar(
        title: const Text(
          'Configurações',
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
              'Ajustes do aplicativo',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Toque em uma opção para abrir o detalhe (em construção).',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            _cardMenu(
              children: [
                _itemMenu(
                  icon: Icons.shield_outlined,
                  cor: _diPertinRoxo,
                  titulo: 'Conta & Segurança',
                  subtitulo: 'Senha, e-mail e dados da conta',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ContaSegurancaScreen(),
                      ),
                    );
                  },
                ),
                Divider(height: 1, color: Colors.grey.shade200),
                _itemMenu(
                  icon: Icons.map_outlined,
                  cor: _diPertinLaranja,
                  titulo: 'Meus Endereços',
                  subtitulo: 'Gerencie endereços de entrega',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MeusEnderecosScreen(),
                      ),
                    );
                  },
                ),
                Divider(height: 1, color: Colors.grey.shade200),
                _itemMenu(
                  icon: Icons.chat_bubble_outline_rounded,
                  cor: _diPertinRoxo,
                  titulo: 'Configuração do chat',
                  subtitulo: 'Alertas de suporte e atendimento',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ConfiguracaoChatScreen(),
                      ),
                    );
                  },
                ),
                Divider(height: 1, color: Colors.grey.shade200),
                _itemMenu(
                  icon: Icons.notifications_outlined,
                  cor: _diPertinLaranja,
                  titulo: 'Configurações de notificações',
                  subtitulo: 'Pedidos, pagamentos, loja, entregas e suporte',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const ConfiguracaoNotificacoesScreen(),
                      ),
                    );
                  },
                ),
                Divider(height: 1, color: Colors.grey.shade200),
                _itemMenu(
                  icon: Icons.policy_outlined,
                  cor: Colors.grey.shade700,
                  titulo: 'Política e privacidade',
                  subtitulo: 'Uso, compras e privacidade',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PoliticaMenuScreen(),
                      ),
                    );
                  },
                ),
                Divider(height: 1, color: Colors.grey.shade200),
                _itemMenu(
                  icon: Icons.info_outline_rounded,
                  cor: Colors.grey.shade700,
                  titulo: 'Sobre',
                  subtitulo: 'Versão e informações do app',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SobreScreen(),
                      ),
                    );
                  },
                ),
                Divider(height: 1, color: Colors.grey.shade200),
                _itemMenu(
                  icon: Icons.person_off_outlined,
                  cor: Colors.red.shade700,
                  titulo: 'Solicitar exclusão de conta',
                  subtitulo:
                      'Operação sensível: exclusão agendada, retenção de 30 dias; '
                      'pode se tornar definitiva após o prazo',
                  onTap: () => abrirFluxoExclusaoConta(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardMenu({required List<Widget> children}) {
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

  Widget _itemMenu({
    required IconData icon,
    required Color cor,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
      trailing: trailing ??
          Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
      onTap: onTap,
    );
  }
}

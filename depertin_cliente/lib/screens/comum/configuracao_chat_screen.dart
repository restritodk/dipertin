// Arquivo: lib/screens/comum/configuracao_chat_screen.dart

import 'package:flutter/material.dart';

import '../../services/chat_notificacoes_prefs.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoTela = Color(0xFFF5F4F8);

/// Configurações de alertas relacionados ao chat de suporte e atendimento.
class ConfiguracaoChatScreen extends StatefulWidget {
  const ConfiguracaoChatScreen({super.key});

  @override
  State<ConfiguracaoChatScreen> createState() => _ConfiguracaoChatScreenState();
}

class _ConfiguracaoChatScreenState extends State<ConfiguracaoChatScreen> {
  bool _carregando = true;
  bool _atendimentoIniciado = true;
  bool _mensagensRecebidas = true;
  bool _atendimentoFinalizado = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final a = await ChatNotificacoesPrefs.atendimentoIniciado();
    final m = await ChatNotificacoesPrefs.mensagensRecebidas();
    final f = await ChatNotificacoesPrefs.atendimentoFinalizado();
    if (!mounted) return;
    setState(() {
      _atendimentoIniciado = a;
      _mensagensRecebidas = m;
      _atendimentoFinalizado = f;
      _carregando = false;
    });
  }

  Future<void> _setIniciado(bool v) async {
    setState(() => _atendimentoIniciado = v);
    await ChatNotificacoesPrefs.setAtendimentoIniciado(v);
  }

  Future<void> _setMensagens(bool v) async {
    setState(() => _mensagensRecebidas = v);
    await ChatNotificacoesPrefs.setMensagensRecebidas(v);
  }

  Future<void> _setFinalizado(bool v) async {
    setState(() => _atendimentoFinalizado = v);
    await ChatNotificacoesPrefs.setAtendimentoFinalizado(v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundoTela,
      appBar: AppBar(
        title: const Text(
          'Configuração do chat',
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
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: _diPertinRoxo))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Notificações do chat',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Escolha quais alertas você deseja receber enquanto usa o '
                    'aplicativo. A ordem segue o fluxo de um atendimento: início, '
                    'mensagens e encerramento.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
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
                      children: [
                        _switchTile(
                          ordem: 1,
                          titulo: 'Atendimento iniciado',
                          descricao:
                              'Quando o suporte começar ou retomar seu atendimento',
                          valor: _atendimentoIniciado,
                          onChanged: _setIniciado,
                          cor: _diPertinRoxo,
                          icon: Icons.support_agent_rounded,
                        ),
                        Divider(height: 1, color: Colors.grey.shade200),
                        _switchTile(
                          ordem: 2,
                          titulo: 'Mensagens recebidas',
                          descricao:
                              'Novas mensagens da equipe nas conversas de suporte',
                          valor: _mensagensRecebidas,
                          onChanged: _setMensagens,
                          cor: _diPertinLaranja,
                          icon: Icons.mark_chat_unread_outlined,
                        ),
                        Divider(height: 1, color: Colors.grey.shade200),
                        _switchTile(
                          ordem: 3,
                          titulo: 'Atendimento finalizado',
                          descricao:
                              'Quando o atendimento for encerrado pela equipe',
                          valor: _atendimentoFinalizado,
                          onChanged: _setFinalizado,
                          cor: _diPertinRoxo,
                          icon: Icons.task_alt_rounded,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.blue.shade100,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: Colors.blue.shade800,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Estas opções aplicam-se aos alertas exibidos com o '
                            'app aberto. Com o app em segundo plano ou fechado, o '
                            'sistema do celular pode ainda mostrar notificações '
                            'conforme as permissões gerais do DiPertin.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: Colors.blueGrey.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _switchTile({
    required int ordem,
    required String titulo,
    required String descricao,
    required bool valor,
    required ValueChanged<bool> onChanged,
    required Color cor,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$ordem',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: cor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: cor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  descricao,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey.shade600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: valor,
            onChanged: onChanged,
            activeThumbColor: _diPertinLaranja,
            activeTrackColor: _diPertinLaranja.withValues(alpha: 0.45),
          ),
        ],
      ),
    );
  }
}

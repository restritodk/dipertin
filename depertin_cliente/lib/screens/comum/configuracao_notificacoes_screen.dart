// Arquivo: lib/screens/comum/configuracao_notificacoes_screen.dart

import 'package:flutter/material.dart';

import '../../services/notificacoes_prefs.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoTela = Color(0xFFF5F4F8);

/// Preferências globais de push (app em primeiro plano). Alinhado aos tipos FCM do backend.
class ConfiguracaoNotificacoesScreen extends StatefulWidget {
  const ConfiguracaoNotificacoesScreen({super.key});

  @override
  State<ConfiguracaoNotificacoesScreen> createState() =>
      _ConfiguracaoNotificacoesScreenState();
}

class _ConfiguracaoNotificacoesScreenState
    extends State<ConfiguracaoNotificacoesScreen> {
  bool _carregando = true;

  bool _clientePedidos = true;
  bool _clientePagamentos = true;
  bool _promocoes = true;
  bool _lojaNovoPedido = true;
  bool _entregadorCorrida = true;
  bool _chatInicio = true;
  bool _chatMensagens = true;
  bool _chatFim = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final v = await Future.wait([
      NotificacoesPrefs.clientePedidosECompras(),
      NotificacoesPrefs.clientePagamentos(),
      NotificacoesPrefs.promocoesENovidades(),
      NotificacoesPrefs.lojaNovosPedidos(),
      NotificacoesPrefs.entregadorCorridas(),
      NotificacoesPrefs.chatAtendimentoIniciado(),
      NotificacoesPrefs.chatMensagensRecebidas(),
      NotificacoesPrefs.chatAtendimentoFinalizado(),
    ]);
    if (!mounted) return;
    setState(() {
      _clientePedidos = v[0];
      _clientePagamentos = v[1];
      _promocoes = v[2];
      _lojaNovoPedido = v[3];
      _entregadorCorrida = v[4];
      _chatInicio = v[5];
      _chatMensagens = v[6];
      _chatFim = v[7];
      _carregando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundoTela,
      appBar: AppBar(
        title: const Text(
          'Configurações de notificações',
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
                    'Escolha o que deseja receber',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'As opções abaixo valem para alertas com o aplicativo aberto. '
                    'Tipos marcados no servidor (pedidos, suporte, corridas) '
                    'respeitam sua escolha aqui quando o DiPertin estiver em uso.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),

                  _secaoTitulo('Cliente', Icons.person_outline_rounded),
                  const SizedBox(height: 10),
                  _card([
                    _switchLinha(
                      titulo: 'Pedidos e compras',
                      subtitulo:
                          'Confirmações e mudanças de status do seu pedido (preparo, envio, entrega)',
                      valor: _clientePedidos,
                      onChanged: (b) async {
                        setState(() => _clientePedidos = b);
                        await NotificacoesPrefs.setClientePedidosECompras(b);
                      },
                      icon: Icons.receipt_long_outlined,
                      cor: _diPertinRoxo,
                    ),
                    _div(),
                    _switchLinha(
                      titulo: 'Pagamentos',
                      subtitulo:
                          'PIX, cartão e confirmações ou alertas de pagamento',
                      valor: _clientePagamentos,
                      onChanged: (b) async {
                        setState(() => _clientePagamentos = b);
                        await NotificacoesPrefs.setClientePagamentos(b);
                      },
                      icon: Icons.payments_outlined,
                      cor: _diPertinLaranja,
                    ),
                    _div(),
                    _switchLinha(
                      titulo: 'Promoções e novidades',
                      subtitulo:
                          'Ofertas, cupons e comunicações promocionais do app',
                      valor: _promocoes,
                      onChanged: (b) async {
                        setState(() => _promocoes = b);
                        await NotificacoesPrefs.setPromocoesENovidades(b);
                      },
                      icon: Icons.local_offer_outlined,
                      cor: _diPertinRoxo,
                    ),
                  ]),

                  const SizedBox(height: 22),
                  _secaoTitulo('Lojista', Icons.storefront_outlined),
                  const SizedBox(height: 10),
                  _card([
                    _switchLinha(
                      titulo: 'Novos pedidos na loja',
                      subtitulo:
                          'Quando um cliente realizar um pedido para o seu estabelecimento',
                      valor: _lojaNovoPedido,
                      onChanged: (b) async {
                        setState(() => _lojaNovoPedido = b);
                        await NotificacoesPrefs.setLojaNovosPedidos(b);
                      },
                      icon: Icons.notifications_active_outlined,
                      cor: _diPertinLaranja,
                    ),
                  ]),

                  const SizedBox(height: 22),
                  _secaoTitulo('Entregador', Icons.delivery_dining_rounded),
                  const SizedBox(height: 10),
                  _card([
                    _switchLinha(
                      titulo: 'Corridas e pedidos prontos',
                      subtitulo:
                          'Quando houver entrega disponível ou pedido liberado pela loja',
                      valor: _entregadorCorrida,
                      onChanged: (b) async {
                        setState(() => _entregadorCorrida = b);
                        await NotificacoesPrefs.setEntregadorCorridas(b);
                      },
                      icon: Icons.electric_moped_outlined,
                      cor: _diPertinRoxo,
                    ),
                  ]),

                  const SizedBox(height: 22),
                  _secaoTitulo(
                    'Suporte e chat',
                    Icons.support_agent_rounded,
                  ),
                  const SizedBox(height: 10),
                  _card([
                    _switchLinha(
                      titulo: 'Atendimento iniciado',
                      subtitulo:
                          'Quando o suporte iniciar ou retomar seu atendimento',
                      valor: _chatInicio,
                      onChanged: (b) async {
                        setState(() => _chatInicio = b);
                        await NotificacoesPrefs.setChatAtendimentoIniciado(b);
                      },
                      icon: Icons.play_circle_outline_rounded,
                      cor: _diPertinRoxo,
                    ),
                    _div(),
                    _switchLinha(
                      titulo: 'Mensagens recebidas',
                      subtitulo: 'Novas mensagens da equipe no chat de suporte',
                      valor: _chatMensagens,
                      onChanged: (b) async {
                        setState(() => _chatMensagens = b);
                        await NotificacoesPrefs.setChatMensagensRecebidas(b);
                      },
                      icon: Icons.mark_chat_unread_outlined,
                      cor: _diPertinLaranja,
                    ),
                    _div(),
                    _switchLinha(
                      titulo: 'Atendimento finalizado',
                      subtitulo:
                          'Quando o atendimento for encerrado pela equipe',
                      valor: _chatFim,
                      onChanged: (b) async {
                        setState(() => _chatFim = b);
                        await NotificacoesPrefs.setChatAtendimentoFinalizado(b);
                      },
                      icon: Icons.task_alt_rounded,
                      cor: _diPertinRoxo,
                    ),
                  ]),

                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade100),
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
                            'Com o app em segundo plano ou fechado, o sistema '
                            'do celular pode ainda exibir notificações conforme '
                            'as permissões gerais. A mesma tela '
                            '"Configuração do chat" altera os itens de suporte '
                            'aqui — as preferências são únicas.',
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

  Widget _secaoTitulo(String texto, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: _diPertinRoxo),
        const SizedBox(width: 8),
        Text(
          texto,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade800,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _card(List<Widget> children) {
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

  Widget _div() => Divider(height: 1, color: Colors.grey.shade200);

  Widget _switchLinha({
    required String titulo,
    required String subtitulo,
    required bool valor,
    required ValueChanged<bool> onChanged,
    required IconData icon,
    required Color cor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.12),
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
                  subtitulo,
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

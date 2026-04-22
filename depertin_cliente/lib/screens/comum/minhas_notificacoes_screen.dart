import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/fcm_notification_eventos.dart';
import '../../services/fcm_rota.dart';
import '../../services/notificacoes_historico_service.dart';
import '../lojista/lojista_form_screen.dart';
import '../entregador/entregador_form_screen.dart';
import '../entregador/entregador_carteira_screen.dart';
import '../cliente/chat_suporte_screen.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);

class MinhasNotificacoesScreen extends StatefulWidget {
  /// `role` do usuário (cliente | lojista | entregador) usado como filtro padrão.
  final String role;
  const MinhasNotificacoesScreen({super.key, required this.role});

  @override
  State<MinhasNotificacoesScreen> createState() =>
      _MinhasNotificacoesScreenState();
}

class _MinhasNotificacoesScreenState extends State<MinhasNotificacoesScreen> {
  final Set<String> _selecionados = <String>{};
  bool _modoSelecao = false;
  bool _processando = false;

  /// IDs das notificações visíveis após o filtro por perfil — usado pelo
  /// botão "Selecionar todas".
  List<String> _idsVisiveisAtual = const <String>[];

  String get _segmentoDoRole {
    switch (widget.role) {
      case 'lojista':
        return FcmNotificationEventos.segmentoLoja;
      case 'entregador':
        return FcmNotificationEventos.segmentoEntregador;
      default:
        return FcmNotificationEventos.segmentoCliente;
    }
  }

  void _alternarSelecao(String id) {
    setState(() {
      if (_selecionados.contains(id)) {
        _selecionados.remove(id);
        if (_selecionados.isEmpty) _modoSelecao = false;
      } else {
        _selecionados.add(id);
        _modoSelecao = true;
      }
    });
  }

  void _iniciarSelecao(String id) {
    setState(() {
      _modoSelecao = true;
      _selecionados.add(id);
    });
  }

  void _sairSelecao() {
    setState(() {
      _modoSelecao = false;
      _selecionados.clear();
    });
  }

  void _selecionarTodas() {
    if (_idsVisiveisAtual.isEmpty) return;
    setState(() {
      _modoSelecao = true;
      _selecionados
        ..clear()
        ..addAll(_idsVisiveisAtual);
    });
  }

  Future<void> _marcarSelecionadosComoLidos() async {
    if (_processando) return;
    final ids = _selecionados.toList();
    setState(() => _processando = true);
    try {
      await NotificacoesHistoricoService.marcarComoLidas(ids);
      if (!mounted) return;
      _sairSelecao();
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _deletarSelecionados() async {
    if (_processando) return;
    final ids = _selecionados.toList();
    if (ids.isEmpty) return;

    final confirma = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir notificações'),
        content: Text(
          ids.length == 1
              ? 'Deseja excluir esta notificação?'
              : 'Deseja excluir ${ids.length} notificações?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirma != true) return;
    if (!mounted) return;

    setState(() => _processando = true);
    bool sucesso = false;
    try {
      sucesso = await NotificacoesHistoricoService.deletar(ids);
    } catch (_) {
      sucesso = false;
    }
    if (!mounted) return;
    _sairSelecao();
    setState(() => _processando = false);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.clearSnackBars();
    messenger?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        backgroundColor: sucesso ? _diPertinRoxo : Colors.red.shade700,
        content: Text(
          sucesso
              ? (ids.length == 1
                  ? 'Notificação excluída.'
                  : '${ids.length} notificações excluídas.')
              : 'Não foi possível excluir. Tente novamente.',
        ),
      ),
    );
  }

  Future<void> _marcarTodasComoLidas() async {
    if (_processando) return;
    setState(() => _processando = true);
    try {
      await NotificacoesHistoricoService.marcarTodasComoLidas();
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  bool _notificacaoPertenceAoPerfil(Map<String, dynamic> dados) {
    final segmento =
        (dados['segmento'] ?? '').toString().trim().toLowerCase();
    if (segmento.isEmpty) {
      // Sem segmento: aparece para todos os perfis (cadastro, suporte, campanhas).
      return true;
    }
    return segmento == _segmentoDoRole;
  }

  void _abrirNotificacao(
    String id,
    Map<String, dynamic> dados,
  ) async {
    if (dados['lida'] != true) {
      unawaited(NotificacoesHistoricoService.marcarComoLidas([id]));
    }

    // Normaliza o payload original recebido do FCM (estava em dados['dados']).
    final payload = <String, dynamic>{};
    final payloadDados = dados['dados'];
    if (payloadDados is Map) {
      payloadDados.forEach((k, v) {
        payload[k.toString()] = v?.toString() ?? '';
      });
    }

    final tipo = (dados['tipo_notificacao'] ??
            payload['tipoNotificacao'] ??
            payload['type'] ??
            '')
        .toString()
        .toLowerCase();

    if (!mounted) return;

    // 1) Cadastro de lojista (aprovado/recusado) → tela "Ser lojista".
    if (tipo.contains('lojista_cadastro') ||
        tipo.contains('cadastro_aprovado') && widget.role == 'lojista' ||
        tipo.contains('cadastro_recusado') && widget.role == 'lojista') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LojistaFormScreen()),
      );
      return;
    }

    // 2) Cadastro de entregador (aprovado/recusado) → tela "Ser entregador".
    if (tipo.contains('entregador_cadastro') ||
        (tipo.contains('cadastro') && widget.role == 'entregador')) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EntregadorFormScreen()),
      );
      return;
    }

    // 3) Saque pago / estorno de saque → carteira do entregador ou do lojista.
    if (tipo.contains('saque') || tipo.contains('estorno_saque')) {
      if (widget.role == 'entregador') {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const EntregadorCarteiraScreen(),
          ),
        );
        return;
      }
      // Lojista: carteira vive no painel web; mantemos o dashboard como destino.
      Navigator.pushNamed(context, '/home');
      return;
    }

    // 4) Suporte (mensagens, abertura, encerramento) → chat de suporte.
    if (tipo.contains('suporte') || tipo.contains('atendimento')) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ChatSuporteScreen()),
      );
      return;
    }

    // 5) Demais tipos (pedidos, pagamentos, nova entrega, campanhas, etc.)
    //    delegam para a rota nomeada já definida em rotaPorPayloadFcm.
    final rota = rotaPorPayloadFcm(payload);
    Navigator.pushNamed(context, rota);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F6FB),
      appBar: AppBar(
        backgroundColor: _diPertinRoxo,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _modoSelecao
              ? '${_selecionados.length} selecionada${_selecionados.length == 1 ? '' : 's'}'
              : 'Minhas notificações',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: _modoSelecao
            ? IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: _sairSelecao,
              )
            : null,
        actions: _modoSelecao
            ? [
                IconButton(
                  icon: const Icon(Icons.select_all_rounded,
                      color: Colors.white),
                  tooltip: 'Selecionar todas',
                  onPressed: _processando ? null : _selecionarTodas,
                ),
                IconButton(
                  icon: const Icon(Icons.mark_email_read_outlined,
                      color: Colors.white),
                  tooltip: 'Marcar como lidas',
                  onPressed: _processando ? null : _marcarSelecionadosComoLidos,
                ),
                IconButton(
                  icon:
                      const Icon(Icons.delete_outline, color: Colors.white),
                  tooltip: 'Excluir',
                  onPressed: _processando ? null : _deletarSelecionados,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.done_all_rounded,
                      color: Colors.white),
                  tooltip: 'Marcar todas como lidas',
                  onPressed: _processando ? null : _marcarTodasComoLidas,
                ),
              ],
      ),
      body: uid == null
          ? const _EstadoVazio(
              icone: Icons.lock_outline,
              titulo: 'Faça login para ver suas notificações',
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: NotificacoesHistoricoService.streamLista(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child:
                        CircularProgressIndicator(color: _diPertinLaranja),
                  );
                }
                final docs = (snap.data?.docs ?? []).where((d) {
                  return _notificacaoPertenceAoPerfil(d.data());
                }).toList();

                // Mantém a lista de IDs visíveis para o botão "Selecionar
                // todas". Atualiza fora do ciclo de build.
                final idsVisiveis = docs.map((d) => d.id).toList();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (_idsVisiveisAtual.length != idsVisiveis.length ||
                      !_idsVisiveisAtual
                          .toSet()
                          .containsAll(idsVisiveis)) {
                    _idsVisiveisAtual = idsVisiveis;
                  }
                });

                if (docs.isEmpty) {
                  return const _EstadoVazio(
                    icone: Icons.notifications_none_outlined,
                    titulo: 'Você ainda não tem notificações',
                    subtitulo:
                        'As notificações que chegarem aparecerão aqui para você consultar a qualquer momento.',
                  );
                }

                return Stack(
                  children: [
                    ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 14),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (ctx, i) {
                        final d = docs[i];
                        final dados = d.data();
                        final id = d.id;
                        return _NotificacaoTile(
                          id: id,
                          dados: dados,
                          selecionado: _selecionados.contains(id),
                          modoSelecao: _modoSelecao,
                          onTap: () {
                            if (_processando) return;
                            if (_modoSelecao) {
                              _alternarSelecao(id);
                            } else {
                              _abrirNotificacao(id, dados);
                            }
                          },
                          onLongPress: _processando
                              ? null
                              : () => _iniciarSelecao(id),
                        );
                      },
                    ),
                    if (_processando)
                      Positioned.fill(
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.08),
                          child: const Center(
                            child: CircularProgressIndicator(
                                color: _diPertinLaranja),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _NotificacaoTile extends StatelessWidget {
  final String id;
  final Map<String, dynamic> dados;
  final bool selecionado;
  final bool modoSelecao;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _NotificacaoTile({
    required this.id,
    required this.dados,
    required this.selecionado,
    required this.modoSelecao,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final titulo = (dados['titulo'] ?? '').toString();
    final corpo = (dados['corpo'] ?? '').toString();
    final lida = dados['lida'] == true;
    final tipoRaw =
        (dados['tipo_notificacao'] ?? '').toString().toLowerCase();
    final criado = dados['criado_em'];
    final dataTexto = criado is Timestamp
        ? DateFormat("dd 'de' MMM • HH:mm", 'pt_BR').format(criado.toDate())
        : '';

    final icone = _iconeParaTipo(tipoRaw);
    final corAcento = _corParaTipo(tipoRaw);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selecionado
                ? _diPertinRoxo.withValues(alpha: 0.08)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selecionado
                  ? _diPertinRoxo
                  : (lida
                      ? const Color(0xFFE5E7EB)
                      : corAcento.withValues(alpha: 0.4)),
              width: selecionado ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (modoSelecao)
                Padding(
                  padding: const EdgeInsets.only(right: 10, top: 2),
                  child: Icon(
                    selecionado
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked,
                    color: selecionado ? _diPertinRoxo : Colors.grey,
                    size: 22,
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: corAcento.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icone, color: corAcento, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            titulo.isEmpty
                                ? 'Notificação do DiPertin'
                                : titulo,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: lida
                                  ? FontWeight.w600
                                  : FontWeight.w800,
                              color: Colors.black.withValues(
                                  alpha: lida ? 0.78 : 1.0),
                            ),
                          ),
                        ),
                        if (!lida)
                          Container(
                            width: 9,
                            height: 9,
                            margin: const EdgeInsets.only(left: 8),
                            decoration: const BoxDecoration(
                              color: _diPertinLaranja,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (corpo.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        corpo,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Colors.black
                              .withValues(alpha: lida ? 0.55 : 0.72),
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (dataTexto.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        dataTexto,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconeParaTipo(String tipo) {
    if (tipo.contains('pedido') || tipo.contains('order')) {
      return Icons.receipt_long_outlined;
    }
    if (tipo.contains('pagamento') || tipo.contains('payment')) {
      return Icons.payments_outlined;
    }
    if (tipo.contains('corrida') ||
        tipo.contains('entrega') ||
        tipo.contains('dispatch')) {
      return Icons.delivery_dining_outlined;
    }
    if (tipo.contains('suporte') || tipo.contains('ticket')) {
      return Icons.support_agent_outlined;
    }
    if (tipo.contains('saque')) return Icons.account_balance_wallet_outlined;
    if (tipo.contains('cadastro') || tipo.contains('lojista')) {
      return Icons.storefront_outlined;
    }
    if (tipo.contains('estorno')) return Icons.sync_alt_rounded;
    if (tipo.contains('campanha') || tipo.contains('promocao')) {
      return Icons.campaign_outlined;
    }
    return Icons.notifications_outlined;
  }

  static Color _corParaTipo(String tipo) {
    if (tipo.contains('pagamento') || tipo.contains('payment')) {
      return const Color(0xFF059669);
    }
    if (tipo.contains('corrida') ||
        tipo.contains('entrega') ||
        tipo.contains('dispatch')) {
      return _diPertinLaranja;
    }
    if (tipo.contains('suporte') || tipo.contains('ticket')) {
      return const Color(0xFF2563EB);
    }
    if (tipo.contains('saque')) return const Color(0xFF0E7490);
    if (tipo.contains('cadastro') || tipo.contains('lojista')) {
      return _diPertinRoxo;
    }
    if (tipo.contains('estorno')) return const Color(0xFFDC2626);
    return _diPertinRoxo;
  }
}

class _EstadoVazio extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String? subtitulo;
  const _EstadoVazio({
    required this.icone,
    required this.titulo,
    this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _diPertinRoxo.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icone, size: 56, color: _diPertinRoxo),
            ),
            const SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _diPertinRoxo,
              ),
            ),
            if (subtitulo != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitulo!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

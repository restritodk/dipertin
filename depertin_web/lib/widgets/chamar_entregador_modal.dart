import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/services/firebase_functions_config.dart';
import 'package:depertin_web/utils/codigo_pedido.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Status da corrida no dispatch
enum StatusCorrida {
  procurando,
  aceito,
  indoLoja,
  emRota,
  concluido,
  cancelado,
}

/// Modal de acompanhamento de chamada de entregador - estilo Uber/iFood
class ChamarEntregadorModal extends StatefulWidget {
  final String pedidoId;
  final String uidLoja;
  final String nomeCliente;
  final String tipoEntrega;
  final double? valorCorrida;
  final VoidCallback? onCancelar;
  final VoidCallback? onConcluir;
  final bool jaSolicitou;

  /// Categoria de entrega escolhida pelo lojista (ex.: `moto`, `carro`).
  /// Usada quando o próprio modal dispara o despacho (`jaSolicitou == false`).
  final String? tipoSolicitado;

  const ChamarEntregadorModal({
    super.key,
    required this.pedidoId,
    required this.uidLoja,
    required this.nomeCliente,
    required this.tipoEntrega,
    this.valorCorrida,
    this.onCancelar,
    this.onConcluir,
    this.jaSolicitou = false,
    this.tipoSolicitado,
  });

  static Future<void> mostrar({
    required BuildContext context,
    required String pedidoId,
    required String uidLoja,
    required String nomeCliente,
    required String tipoEntrega,
    double? valorCorrida,
    VoidCallback? onCancelar,
    VoidCallback? onConcluir,
    bool jaSolicitou = false,
    String? tipoSolicitado,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ChamarEntregadorModal(
        pedidoId: pedidoId,
        uidLoja: uidLoja,
        nomeCliente: nomeCliente,
        tipoEntrega: tipoEntrega,
        valorCorrida: valorCorrida,
        onCancelar: onCancelar,
        onConcluir: onConcluir,
        jaSolicitou: jaSolicitou,
        tipoSolicitado: tipoSolicitado,
      ),
    );
  }

  @override
  State<ChamarEntregadorModal> createState() => _ChamarEntregadorModalState();
}

class _ChamarEntregadorModalState extends State<ChamarEntregadorModal> {
  static const _roxo = Color(0xFF6C3AEE);
  static const _laranja = Color(0xFFE65100);
  static const _verde = Color(0xFF15803D);
  static const _cinza = Color(0xFF6B7280);
  static const _texto = Color(0xFF1A1A2E);

  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  StreamSubscription<DocumentSnapshot>? _listener;
  Map<String, dynamic>? _pedidoData;
  bool _cancelando = false;
  bool _concluido = false;
  bool _erroSolicitacao = false;
  String _erroMensagem = '';
  bool _solicitacaoIniciada = false;

  /// Só consideramos que o pedido "voltou para em_preparo" (cancelamento do
  /// despacho) depois de termos confirmado que o despacho ficou ativo
  /// (`aguardando_entregador` ou entregador atribuído). Isso evita o falso
  /// cancelamento quando o primeiro snapshot do listener vem do cache local
  /// ainda com o status anterior (`em_preparo`).
  bool _despachoConfirmado = false;
  bool _encerrando = false;

  DateTime? _horaSolicitacao;
  DateTime? _horaAceito;
  DateTime? _horaIndoLoja;
  DateTime? _horaRetirada;
  DateTime? _horaEmRota;
  DateTime? _horaEntrega;

  String _entregadorNome = '';
  String _entregadorTelefone = '';
  String _entregadorVeiculo = '';
  String _entregadorPlaca = '';
  String _entregadorFotoUrl = '';
  double _entregadorAvaliacao = 0.0;

  @override
  void initState() {
    super.initState();
    _horaSolicitacao = DateTime.now();
    _iniciarListener();

    // Se ainda não solicitou, faz a solicitação agora
    if (!widget.jaSolicitou && !_solicitacaoIniciada) {
      _solicitacaoIniciada = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _solicitarEntregador();
      });
    }
  }

  Future<void> _solicitarEntregador() async {
    if (!mounted) return;

    // Primeiro verifica se o pedido já está em aguardando_entregador
    try {
      final doc = await FirebaseFirestore.instance
          .collection('pedidos')
          .doc(widget.pedidoId)
          .get();

      if (!mounted) return;

      final data = doc.data();
      if (data == null) {
        setState(() {
          _erroSolicitacao = true;
          _erroMensagem = 'Pedido não encontrado.';
        });
        return;
      }

      final status = data['status']?.toString() ?? '';

      // Se já está em aguardando_entregador, não precisa chamar a função novamente
      if (status == 'aguardando_entregador') {
        debugPrint('Pedido já está aguardando entregador, iniciando listener...');
        return;
      }

      // Se não está em preparo ou pronto, não pode iniciar despacho
      if (status != 'em_preparo' && status != 'preparando' && status != 'pronto') {
        setState(() {
          _erroSolicitacao = true;
          _erroMensagem = 'O pedido precisa estar em preparo ou pronto para solicitar entregador. Status atual: $status';
        });
        return;
      }
    } catch (e) {
      debugPrint('Erro ao verificar status: $e');
    }

    setState(() {
      _erroSolicitacao = false;
      _erroMensagem = '';
    });

    try {
      final result = await callFirebaseFunctionSafe(
        'lojistaSolicitarDespachoEntregador',
        parameters: <String, dynamic>{
          'pedidoId': widget.pedidoId,
          'tipoEntregaSolicitado': widget.tipoSolicitado,
        },
      );

      debugPrint('lojistaSolicitarDespachoEntregador result: $result');

      if (!mounted) return;
    } on CallableHttpException catch (e) {
      if (!mounted) return;
      setState(() {
        _erroSolicitacao = true;
        _erroMensagem = e.message;
      });
      debugPrint('Erro HTTP: ${e.code} - ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erroSolicitacao = true;
        _erroMensagem = 'Erro ao buscar entregadores: $e';
      });
      debugPrint('Erro: $e');
    }
  }

  @override
  void dispose() {
    _listener?.cancel();
    super.dispose();
  }

  void _iniciarListener() {
    final ref = FirebaseFirestore.instance.collection('pedidos').doc(widget.pedidoId);
    _listener = ref.snapshots().listen(_onPedidoUpdate, onError: (e) {
      debugPrint('Erro no listener: $e');
    });
  }

  void _onPedidoUpdate(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;

    final data = snap.data();
    if (data == null) return;

    setState(() {
      _pedidoData = data;
      _processarStatus(data);
    });
  }

  void _processarStatus(Map<String, dynamic> data) {
    final status = data['status']?.toString() ?? '';
    final entregadorId = data['entregador_id']?.toString() ?? '';

    // Marca o despacho como confirmado assim que vemos o pedido em um estado
    // de corrida ativa. A partir daí, um eventual retorno para `em_preparo`
    // significa que a chamada foi realmente cancelada/abortada.
    const statusDespachoAtivo = {
      'aguardando_entregador',
      'entregador_indo_loja',
      'saiu_entrega',
      'em_rota',
      'a_caminho',
    };
    if (statusDespachoAtivo.contains(status) || entregadorId.isNotEmpty) {
      _despachoConfirmado = true;
    }

    if (entregadorId.isNotEmpty) {
      _entregadorNome = data['entregador_nome']?.toString() ?? 'Entregador';
      _entregadorTelefone = data['entregador_telefone']?.toString() ?? '';
      _entregadorVeiculo = data['entregador_veiculo']?.toString() ?? '';
      _entregadorPlaca = data['entregador_placa']?.toString() ?? '';
      _entregadorFotoUrl = data['entregador_foto_url']?.toString() ?? '';
      _entregadorAvaliacao = (data['entregador_avaliacao'] ?? 0.0).toDouble();
    }

    if (data['busca_entregador_inicio'] != null) {
      _horaSolicitacao = (data['busca_entregador_inicio'] as Timestamp).toDate();
    }
    if (data['despacho_aceito_em'] != null) {
      _horaAceito = (data['despacho_aceito_em'] as Timestamp).toDate();
    }
    if (data['entregador_aceite_em'] != null) {
      _horaAceito = (data['entregador_aceite_em'] as Timestamp).toDate();
    }
    if (data['entregador_indo_loja_em'] != null) {
      _horaIndoLoja = (data['entregador_indo_loja_em'] as Timestamp).toDate();
    }
    if (data['entregador_chegou_loja_em'] != null) {
      _horaIndoLoja = (data['entregador_chegou_loja_em'] as Timestamp).toDate();
    }
    if (data['pedido_retirado_em'] != null) {
      _horaRetirada = (data['pedido_retirado_em'] as Timestamp).toDate();
    }
    if (data['saiu_entrega_em'] != null) {
      _horaEmRota = (data['saiu_entrega_em'] as Timestamp).toDate();
    }
    if (data['entregue_em'] != null) {
      _horaEntrega = (data['entregue_em'] as Timestamp).toDate();
    }

    if (status == 'entregue' && !_concluido) {
      _concluido = true;
      _horaEntrega = DateTime.now();
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) {
          widget.onConcluir?.call();
          Navigator.of(context).pop();
        }
      });
      return;
    }

    // Cancelamento real: pedido cancelado, ou voltou para `em_preparo` DEPOIS
    // de o despacho já ter sido confirmado (abort/cancelamento da corrida).
    final foiCancelado = status == 'cancelado' ||
        (status == 'em_preparo' && _despachoConfirmado);
    if (foiCancelado && !_encerrando) {
      _encerrando = true;
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          widget.onCancelar?.call();
          Navigator.of(context).pop();
        }
      });
    }
  }

  StatusCorrida _getStatusCorrida() {
    if (_concluido) return StatusCorrida.concluido;
    final data = _pedidoData;
    if (data == null) return StatusCorrida.procurando;

    final status = data['status']?.toString() ?? '';
    final entregadorId = data['entregador_id']?.toString() ?? '';

    if (status == 'cancelado') return StatusCorrida.cancelado;

    if (entregadorId.isEmpty) {
      if (status == 'aguardando_entregador') {
        return StatusCorrida.procurando;
      }
      return StatusCorrida.procurando;
    }

    switch (status) {
      case 'entregador_indo_loja':
        return StatusCorrida.indoLoja;
      case 'pronto':
      case 'saiu_entrega':
      case 'em_rota':
      case 'a_caminho':
        return StatusCorrida.emRota;
      case 'entregue':
        return StatusCorrida.concluido;
      default:
        return StatusCorrida.aceito;
    }
  }

  bool _podeCancelar() {
    final status = _getStatusCorrida();
    return status != StatusCorrida.emRota &&
        status != StatusCorrida.concluido &&
        status != StatusCorrida.cancelado;
  }

  Future<void> _cancelarSolicitacao() async {
    if (_cancelando) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar solicitação?'),
        content: const Text(
          'A busca por entregador será encerrada. Você poderá solicitar novamente quando quiser.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim, cancelar'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    setState(() => _cancelando = true);

    try {
      await callFirebaseFunctionSafe(
        'lojistaCancelarChamadaEntregador',
        parameters: <String, dynamic>{
          'pedidoId': widget.pedidoId,
        },
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onCancelar?.call();
      }
    } catch (e) {
      debugPrint('Erro ao cancelar: $e');
      if (mounted) {
        setState(() => _cancelando = false);
        // Tenta cancelar via Firestore direto
        try {
          await FirebaseFirestore.instance
              .collection('pedidos')
              .doc(widget.pedidoId)
              .update({
            'status': 'em_preparo',
            'despacho_abort_flag': true,
          });
          if (mounted) {
            Navigator.of(context).pop();
            widget.onCancelar?.call();
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erro ao cancelar: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    }
  }

  String _formatarHora(DateTime? dt) {
    if (dt == null) return '--:--';
    return DateFormat('HH:mm').format(dt);
  }

  String _formaPagamentoLabel() {
    final d = _pedidoData;
    if (d == null) return '—';
    final raw = (d['forma_pagamento'] ??
            d['metodo_pagamento'] ??
            d['pagamento'] ??
            '')
        .toString()
        .toLowerCase();
    if (raw.contains('pix')) return 'PIX';
    if (raw.contains('credito') || raw.contains('crédito')) {
      return 'Cartão de Crédito';
    }
    if (raw.contains('debito') || raw.contains('débito')) {
      return 'Cartão de Débito';
    }
    if (raw.contains('cart')) return 'Cartão';
    if (raw.contains('dinheiro')) return 'Dinheiro';
    if (raw.contains('vale')) return 'Vale';
    return raw.isEmpty ? '—' : raw;
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final status = _getStatusCorrida();
    final size = MediaQuery.of(context).size;
    final larguraModal = size.width > 1180 ? 1100.0 : size.width * 0.94;
    final alturaModal = size.height * 0.86;
    final isCompacto = size.width < 900;

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: larguraModal,
          maxHeight: alturaModal,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const Divider(height: 1, color: Color(0xFFEEF0F3)),
            Flexible(
              child: _erroSolicitacao
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: _buildErroCard(),
                    )
                  : (isCompacto
                      ? _buildConteudoCompacto(status)
                      : _buildConteudoDuasColunas(status)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 12, 18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _roxo.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.delivery_dining, color: _roxo, size: 26),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Entrega do Pedido',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _texto,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Acompanhe o status da entrega em tempo real',
                  style: TextStyle(fontSize: 13, color: _cinza),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: _cinza),
            tooltip: 'Fechar',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _buildConteudoDuasColunas(StatusCorrida status) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 6,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusCard(status),
                const SizedBox(height: 24),
                _buildSecaoTitulo('Status da Entrega'),
                const SizedBox(height: 14),
                _buildTimeline(status),
                const SizedBox(height: 20),
                _buildAvisoNotificacao(),
              ],
            ),
          ),
        ),
        Container(width: 1, color: const Color(0xFFEEF0F3)),
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _buildColunaDireita(status),
          ),
        ),
      ],
    );
  }

  Widget _buildConteudoCompacto(StatusCorrida status) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatusCard(status),
          const SizedBox(height: 20),
          _buildColunaDireita(status),
          const SizedBox(height: 24),
          _buildSecaoTitulo('Status da Entrega'),
          const SizedBox(height: 14),
          _buildTimeline(status),
          const SizedBox(height: 20),
          _buildAvisoNotificacao(),
        ],
      ),
    );
  }

  Widget _buildColunaDireita(StatusCorrida status) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDetalhesEntrega(),
        if (_podeCancelar()) ...[
          const SizedBox(height: 16),
          _buildAvisoCancelamento(),
        ],
        const SizedBox(height: 16),
        _buildEntregadorBloco(status),
        const SizedBox(height: 16),
        _buildHistorico(),
        const SizedBox(height: 20),
        if (_podeCancelar())
          _buildBotaoCancelar()
        else if (status != StatusCorrida.concluido &&
            status != StatusCorrida.cancelado)
          _buildMensagemNaoCancelavel(),
      ],
    );
  }

  Widget _buildSecaoTitulo(String texto) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: _texto,
      ),
    );
  }

  // ----- Card de status atual ------------------------------------------------
  ({IconData icone, Color cor, String titulo, String subtitulo, String descricao})
      _statusVisual(StatusCorrida status) {
    switch (status) {
      case StatusCorrida.procurando:
        return (
          icone: Icons.search,
          cor: _roxo,
          titulo: 'Procurando entregadores',
          subtitulo: 'Aguardando aceite de entregador...',
          descricao: 'Enviamos sua solicitação para entregadores próximos.',
        );
      case StatusCorrida.aceito:
        return (
          icone: Icons.check_circle,
          cor: const Color(0xFF0891B2),
          titulo: 'Entregador encontrado',
          subtitulo: _entregadorNome.isNotEmpty
              ? _entregadorNome
              : 'Um entregador aceitou a corrida.',
          descricao: 'O entregador está se preparando para ir até a loja.',
        );
      case StatusCorrida.indoLoja:
        return (
          icone: Icons.store,
          cor: _laranja,
          titulo: 'A caminho da loja',
          subtitulo: 'O entregador está indo ao estabelecimento.',
          descricao: 'Deixe o pedido pronto para a retirada.',
        );
      case StatusCorrida.emRota:
        return (
          icone: Icons.delivery_dining,
          cor: Colors.blue.shade700,
          titulo: 'Pedido em rota',
          subtitulo: 'O entregador está a caminho do cliente.',
          descricao: 'A entrega está em andamento.',
        );
      case StatusCorrida.concluido:
        return (
          icone: Icons.check_circle,
          cor: _verde,
          titulo: 'Pedido entregue',
          subtitulo: 'Entrega concluída com sucesso!',
          descricao: _horaEntrega != null
              ? 'Concluído às ${_formatarHora(_horaEntrega)}.'
              : 'Pedido entregue e confirmado.',
        );
      case StatusCorrida.cancelado:
        return (
          icone: Icons.cancel,
          cor: Colors.red.shade600,
          titulo: 'Solicitação cancelada',
          subtitulo: 'A busca por entregador foi encerrada.',
          descricao: 'Você pode solicitar novamente quando quiser.',
        );
    }
  }

  Widget _buildStatusCard(StatusCorrida status) {
    final v = _statusVisual(status);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: v.cor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: v.cor.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: status == StatusCorrida.procurando
                ? CircularProgressIndicator(
                    strokeWidth: 3.2,
                    valueColor: AlwaysStoppedAnimation<Color>(v.cor),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: v.cor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(v.icone, color: v.cor, size: 26),
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.titulo,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: v.cor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  v.subtitulo,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  v.descricao,
                  style: const TextStyle(fontSize: 12.5, color: _cinza),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----- Timeline ------------------------------------------------------------
  int _indiceAtivo(StatusCorrida status) {
    switch (status) {
      case StatusCorrida.procurando:
        return 0;
      case StatusCorrida.aceito:
        return 1;
      case StatusCorrida.indoLoja:
        return 2;
      case StatusCorrida.emRota:
        return 4;
      case StatusCorrida.concluido:
        return 5;
      case StatusCorrida.cancelado:
        return 0;
    }
  }

  Widget _buildTimeline(StatusCorrida status) {
    final ativo = _indiceAtivo(status);
    final steps = <_TimelineStepData>[
      _TimelineStepData(
        titulo: 'Solicitação enviada',
        descricao: 'A solicitação foi enviada para os entregadores.',
        hora: _horaSolicitacao,
        icone: Icons.send,
      ),
      _TimelineStepData(
        titulo: 'Entregador aceitou',
        descricao: 'Um entregador aceitou a corrida.',
        hora: _horaAceito,
        icone: Icons.check_circle,
      ),
      _TimelineStepData(
        titulo: 'Chegou na loja',
        descricao: 'O entregador chegou ao estabelecimento.',
        hora: _horaIndoLoja,
        icone: Icons.store,
      ),
      _TimelineStepData(
        titulo: 'Pedido retirado',
        descricao: 'O entregador retirou o pedido.',
        hora: _horaRetirada,
        icone: Icons.inventory_2,
      ),
      _TimelineStepData(
        titulo: 'Em rota',
        descricao: 'O entregador está indo até o cliente.',
        hora: _horaEmRota,
        icone: Icons.delivery_dining,
      ),
      _TimelineStepData(
        titulo: 'Entregue',
        descricao: 'Pedido entregue e confirmado.',
        hora: _horaEntrega,
        icone: Icons.home,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...steps.asMap().entries.map((entry) {
          final idx = entry.key;
          final step = entry.value;
          final isLast = idx == steps.length - 1;
          final concluido = step.hora != null || idx < ativo;
          final estaAtivo = idx == ativo && !concluido;

          Color corIcone;
          if (concluido) {
            corIcone = _verde;
          } else if (estaAtivo) {
            corIcone = _roxo;
          } else {
            corIcone = Colors.grey.shade400;
          }

          final corLinha = concluido
              ? _verde
              : (estaAtivo ? _roxo : Colors.grey.shade300);

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 30,
                  child: Column(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: corIcone.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: estaAtivo
                              ? Border.all(color: corIcone, width: 2)
                              : null,
                        ),
                        child: Icon(
                          concluido ? Icons.check : step.icone,
                          size: concluido ? 17 : 15,
                          color: corIcone,
                        ),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(width: 2, color: corLinha),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                step.titulo,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: estaAtivo
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: concluido || estaAtivo
                                      ? _texto
                                      : Colors.grey.shade500,
                                ),
                              ),
                            ),
                            if (step.hora != null)
                              Text(
                                _formatarHora(step.hora),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          step.descricao,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: concluido || estaAtivo
                                ? Colors.grey.shade600
                                : Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ----- Avisos --------------------------------------------------------------
  Widget _buildAvisoNotificacao() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user_outlined,
              size: 20, color: Colors.blue.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Você será notificado a cada atualização do status da entrega.',
              style: TextStyle(fontSize: 13, color: Colors.blue.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvisoCancelamento() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 20, color: Colors.amber.shade800),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Você poderá cancelar a solicitação até o entregador iniciar a rota.',
              style: TextStyle(fontSize: 12.5, color: Colors.amber.shade900),
            ),
          ),
        ],
      ),
    );
  }

  // ----- Detalhes da entrega -------------------------------------------------
  Widget _buildDetalhesEntrega() {
    final codigo = CodigoPedido.exibir(
        widget.pedidoId, _pedidoData ?? const <String, dynamic>{});
    return _buildCardSecao(
      titulo: 'Detalhes da entrega',
      child: Column(
        children: [
          _buildLinhaInfo(Icons.receipt_long_outlined, 'Pedido', codigo),
          const SizedBox(height: 12),
          _buildLinhaInfo(
              Icons.person_outline, 'Cliente', widget.nomeCliente),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildLinhaInfo(Icons.local_shipping_outlined, 'Tipo',
                    widget.tipoEntrega),
              ),
              Expanded(
                child: _buildLinhaInfo(Icons.payments_outlined, 'Pagamento',
                    _formaPagamentoLabel()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildLinhaInfo(
                    Icons.schedule_outlined, 'Previsão', '20-30 min'),
              ),
              if (widget.valorCorrida != null && widget.valorCorrida! > 0)
                Expanded(
                  child: _buildLinhaInfo(Icons.attach_money,
                      'Taxa', _moeda.format(widget.valorCorrida),
                      destaque: true),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLinhaInfo(IconData icone, String label, String valor,
      {bool destaque = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 1),
              Text(
                valor,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: destaque ? _laranja : _texto,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ----- Entregador ----------------------------------------------------------
  Widget _buildEntregadorBloco(StatusCorrida status) {
    final temEntregador =
        _entregadorNome.isNotEmpty && status != StatusCorrida.procurando;
    return _buildCardSecao(
      titulo: 'Entregador',
      child: temEntregador
          ? _buildEntregadorDados()
          : _buildEntregadorAguardando(),
    );
  }

  Widget _buildEntregadorAguardando() {
    return Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: Colors.grey.shade100,
          child: Icon(Icons.person_outline, color: Colors.grey.shade400, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Aguardando aceitação',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Assim que um entregador aceitar, as informações serão exibidas aqui.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEntregadorDados() {
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: Colors.grey.shade200,
          backgroundImage: _entregadorFotoUrl.isNotEmpty
              ? NetworkImage(_entregadorFotoUrl)
              : null,
          child: _entregadorFotoUrl.isEmpty
              ? const Icon(Icons.delivery_dining, color: _roxo, size: 26)
              : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _entregadorNome.isNotEmpty ? _entregadorNome : 'Entregador',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _texto,
                ),
              ),
              if (_entregadorTelefone.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: _miniLinha(Icons.phone, _entregadorTelefone),
                ),
              if (_entregadorVeiculo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _miniLinha(Icons.two_wheeler, _entregadorVeiculo),
                ),
              if (_entregadorPlaca.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _miniLinha(
                      Icons.confirmation_number_outlined, _entregadorPlaca),
                ),
            ],
          ),
        ),
        if (_entregadorAvaliacao > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star, size: 15, color: Colors.amber),
                const SizedBox(width: 4),
                Text(
                  _entregadorAvaliacao.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.amber.shade800,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _miniLinha(IconData icone, String texto) {
    return Row(
      children: [
        Icon(icone, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            texto,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }

  // ----- Histórico em tempo real ---------------------------------------------
  Widget _buildHistorico() {
    final eventos = <({DateTime hora, String label})>[];
    void add(DateTime? h, String l) {
      if (h != null) eventos.add((hora: h, label: l));
    }

    add(_horaSolicitacao, 'Solicitação enviada');
    add(_horaAceito, 'Entregador aceitou');
    add(_horaIndoLoja, 'Chegou na loja');
    add(_horaRetirada, 'Pedido retirado');
    add(_horaEmRota, 'Em rota');
    add(_horaEntrega, 'Pedido entregue');
    eventos.sort((a, b) => a.hora.compareTo(b.hora));

    return _buildCardSecao(
      titulo: 'Histórico em tempo real',
      child: eventos.isEmpty
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    'As atualizações aparecerão aqui conforme o andamento da entrega.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.podcasts, size: 20, color: _roxo.withValues(alpha: 0.5)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: eventos
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: _verde,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _formatarHora(e.hora),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _texto,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              e.label,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  // ----- Helpers de cartão/botões --------------------------------------------
  Widget _buildCardSecao({required String titulo, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEF0F3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: _texto,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildBotaoCancelar() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: _cancelando ? null : _cancelarSolicitacao,
        icon: _cancelando
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.red),
                ),
              )
            : const Icon(Icons.close),
        label: Text(_cancelando ? 'Cancelando...' : 'Cancelar solicitação'),
      ),
    );
  }

  Widget _buildMensagemNaoCancelavel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'A solicitação não pode ser cancelada pois a entrega já foi iniciada.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
          const SizedBox(height: 12),
          Text(
            'Erro na solicitação',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.red.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _erroMensagem.isNotEmpty
                ? _erroMensagem
                : 'Não foi possível buscar entregadores.',
            style: TextStyle(fontSize: 13, color: Colors.red.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fechar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    setState(() {
                      _erroSolicitacao = false;
                      _erroMensagem = '';
                    });
                    _solicitarEntregador();
                  },
                  child: const Text('Tentar novamente'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelineStepData {
  final String titulo;
  final String descricao;
  final DateTime? hora;
  final IconData icone;

  _TimelineStepData({
    required this.titulo,
    required this.descricao,
    this.hora,
    required this.icone,
  });
}

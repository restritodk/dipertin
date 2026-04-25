// Arquivo: lib/screens/lojista/lojista_pedidos_screen.dart

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:depertin_cliente/constants/pedido_status.dart';
import 'package:depertin_cliente/constants/tipos_entrega.dart';
import 'package:depertin_cliente/services/firebase_functions_config.dart';
import 'package:depertin_cliente/utils/lojista_acesso_app.dart';
import 'package:depertin_cliente/widgets/badge_entregador_acessibilidade.dart';
import 'package:depertin_cliente/widgets/chat_pedido_botao.dart';

import 'widgets/escolher_tipo_entrega_dialog.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);
const Color _diPertinRoxoEscuro = Color(0xFF4A0B7C);
const Color _fundoTela = Color(0xFFF7F5FA);
const Color _tintaForte = Color(0xFF17162A);
const Color _tintaMedia = Color(0xFF5A5870);
const Color _tintaSuave = Color(0xFF8E8BA0);
const Color _bordaSuave = Color(0xFFECE8F2);
const Color _verdeSucesso = Color(0xFF0F9D6B);
const Color _vermelhoPerigo = Color(0xFFDC3545);
const Color _ambarAviso = Color(0xFFB7791F);
const Color _azulInfo = Color(0xFF2E6BE6);

/// Cor principal + fundo suave + borda, por status do pedido.
({Color principal, Color fundo, Color borda}) _paletaStatus(String status) {
  switch (status) {
    case PedidoStatus.pendente:
      return (
        principal: _vermelhoPerigo,
        fundo: const Color(0xFFFFF1F2),
        borda: const Color(0xFFFBD5D8),
      );
    case PedidoStatus.aceito:
    case PedidoStatus.emPreparo:
      return (
        principal: diPertinLaranja,
        fundo: const Color(0xFFFFF6E6),
        borda: const Color(0xFFFFDEA8),
      );
    case PedidoStatus.aguardandoEntregador:
    case PedidoStatus.entregadorIndoLoja:
      return (
        principal: _azulInfo,
        fundo: const Color(0xFFEFF5FE),
        borda: const Color(0xFFC8DAF9),
      );
    case PedidoStatus.saiuEntrega:
    case PedidoStatus.emRota:
    case PedidoStatus.aCaminho:
      return (
        principal: diPertinRoxo,
        fundo: const Color(0xFFF5EDFA),
        borda: const Color(0xFFDCC6EB),
      );
    case PedidoStatus.pronto:
      return (
        principal: const Color(0xFF0F766E),
        fundo: const Color(0xFFE6FAF6),
        borda: const Color(0xFFB6E9DD),
      );
    case PedidoStatus.entregue:
      return (
        principal: _verdeSucesso,
        fundo: const Color(0xFFE7F6EE),
        borda: const Color(0xFFBFE5CF),
      );
    case PedidoStatus.cancelado:
      return (
        principal: _vermelhoPerigo,
        fundo: const Color(0xFFFBEBEC),
        borda: const Color(0xFFF3C7CA),
      );
    default:
      return (
        principal: _tintaMedia,
        fundo: const Color(0xFFF2F1F6),
        borda: _bordaSuave,
      );
  }
}

IconData _iconePorStatus(String status) {
  switch (status) {
    case PedidoStatus.pendente:
      return Icons.mark_chat_unread_rounded;
    case PedidoStatus.aceito:
      return Icons.check_circle_outline_rounded;
    case PedidoStatus.emPreparo:
      return Icons.soup_kitchen_rounded;
    case PedidoStatus.aguardandoEntregador:
      return Icons.radar_rounded;
    case PedidoStatus.entregadorIndoLoja:
      return Icons.directions_bike_rounded;
    case PedidoStatus.saiuEntrega:
    case PedidoStatus.emRota:
    case PedidoStatus.aCaminho:
      return Icons.local_shipping_rounded;
    case PedidoStatus.pronto:
      return Icons.storefront_rounded;
    case PedidoStatus.entregue:
      return Icons.task_alt_rounded;
    case PedidoStatus.cancelado:
      return Icons.cancel_outlined;
    default:
      return Icons.receipt_long_rounded;
  }
}

/// Ex.: "agora", "há 5 min", "há 2 h", "ontem", "12/04 às 14:22".
String _tempoRelativo(Timestamp? ts) {
  if (ts == null) return 'agora';
  final agora = DateTime.now();
  final d = ts.toDate();
  final diff = agora.difference(d);
  if (diff.inSeconds < 45) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 12) return 'há ${diff.inHours} h';
  final mesmaData = agora.year == d.year &&
      agora.month == d.month &&
      agora.day == d.day;
  if (mesmaData) {
    return 'hoje às ${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
  final ontem = agora.subtract(const Duration(days: 1));
  final eraOntem = ontem.year == d.year &&
      ontem.month == d.month &&
      ontem.day == d.day;
  if (eraOntem) {
    return 'ontem às ${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      'às ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

const List<FontFeature> _numerosTabulares = [
  FontFeature.tabularFigures(),
];

class LojistaPedidosScreen extends StatefulWidget {
  const LojistaPedidosScreen({super.key, this.uidLoja});

  final String? uidLoja;

  @override
  State<LojistaPedidosScreen> createState() => _LojistaPedidosScreenState();
}

class _LojistaPedidosScreenState extends State<LojistaPedidosScreen> {
  late final String _uid =
      widget.uidLoja ?? FirebaseAuth.instance.currentUser!.uid;
  final String _authUid = FirebaseAuth.instance.currentUser!.uid;

  late final Stream<QuerySnapshot> _streamPedidosLoja = FirebaseFirestore
      .instance
      .collection('pedidos')
      .where('loja_id', isEqualTo: _uid)
      .snapshots();

  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<QuerySnapshot>? _pedidosSubscription;
  StreamSubscription<DocumentSnapshot>? _userDocSub;
  bool _primeiroCarregamento = true;
  bool _continuarBuscaEntregadorEmProgresso = false;
  final Set<String> _solicitandoEntregadorEmProgresso = <String>{};
  final Set<String> _abrindoConfirmacaoCancelarChamada = <String>{};
  final Set<String> _cancelandoChamadaEmProgresso = <String>{};
  final Set<String> _abrindoConfirmacaoChamarDeNovo = <String>{};
  final Set<String> _chamandoDeNovoEmProgresso = <String>{};

  /// Dono (sem `lojista_owner_uid`) = 3. Colaborador = `painel_colaborador_nivel`.
  /// Apenas nível >= 3 (dono + colaborador nível III) pode ver a caixa financeira.
  int _nivelAcesso = 3;
  bool get _podeVerFinanceiro => _nivelAcesso >= 3;

  @override
  void initState() {
    super.initState();
    _iniciarVigiaDePedidos();
    _escutarNivelAcesso();
  }

  @override
  void dispose() {
    _pedidosSubscription?.cancel();
    _userDocSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _escutarNivelAcesso() {
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(_authUid)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;
      final dados = snap.data() as Map<String, dynamic>;
      final nivel = nivelAcessoLojista(dados);
      if (nivel != _nivelAcesso) {
        setState(() => _nivelAcesso = nivel);
      }
    });
  }

  /// Foto + nome do cliente denormalizados no pedido (`cliente_nome` e
  /// `cliente_foto_perfil`, Fase 3G.3). Evita ler `users/{cliente_id}` —
  /// necessário porque a rule de `users` agora bloqueia leitura cruzada entre
  /// autenticados para proteger CPF/email/telefone/saldo de quem não é lojista.
  Widget _cabecalhoClientePedido(Map<String, dynamic> pedido) {
    final nomeGravado = (pedido['cliente_nome'] ?? '').toString().trim();
    final foto = (pedido['cliente_foto_perfil'] ?? '').toString().trim();
    final nome = nomeGravado.isNotEmpty ? nomeGravado : 'Cliente';

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                diPertinRoxo.withValues(alpha: 0.14),
                diPertinLaranja.withValues(alpha: 0.10),
              ],
            ),
            border: Border.all(color: _bordaSuave),
            image: foto.isNotEmpty
                ? DecorationImage(
                    image: NetworkImage(foto),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          alignment: Alignment.center,
          child: foto.isEmpty
              ? const Icon(Icons.person_rounded, color: diPertinRoxo, size: 22)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CLIENTE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: _tintaSuave,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                nome,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: _tintaForte,
                  letterSpacing: -0.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pillEntrega(bool isRetirada, Map<String, dynamic> pedido) {
    final Color cor = isRetirada ? diPertinLaranja : diPertinRoxo;
    final String texto = isRetirada
        ? 'Retirada no balcão'
        : 'Entrega: ${pedido['endereco_entrega']}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isRetirada
                ? Icons.storefront_rounded
                : Icons.two_wheeler_rounded,
            color: cor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cor,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipStatusPedido(String status, bool isRetirada) {
    final paleta = _paletaStatus(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: paleta.fundo,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: paleta.borda),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconePorStatus(status), size: 14, color: paleta.principal),
          const SizedBox(width: 6),
          Text(
            _rotuloStatusLojista(status, isRetirada),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              color: paleta.principal,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  void _iniciarVigiaDePedidos() {
    _pedidosSubscription = FirebaseFirestore.instance
        .collection('pedidos')
        .where('loja_id', isEqualTo: _uid)
        .snapshots()
        .listen((snapshot) {
          if (_primeiroCarregamento) {
            _primeiroCarregamento = false;
            return;
          }

          for (final change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.added) {
              final pedido = change.doc.data() as Map<String, dynamic>;
              if (pedido['status'] == 'pendente') {
                _tocarSom();
              }
            }
          }
        });
  }

  Future<void> _tocarSom() async {
    try {
      await _audioPlayer.play(AssetSource('sond/pedido.mp3'));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Erro ao tocar som: $e');
      }
    }
  }

  Future<void> _cancelarChamadaEntregador(String pedidoId) async {
    if (_abrindoConfirmacaoCancelarChamada.contains(pedidoId) ||
        _cancelandoChamadaEmProgresso.contains(pedidoId)) {
      return;
    }
    if (mounted) {
      setState(() => _abrindoConfirmacaoCancelarChamada.add(pedidoId));
    }
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar chamada?'),
        content: const Text(
          'A busca por entregador será encerrada. O pedido volta para '
          '"Em preparo" e você poderá tocar em "Solicitar entregador" '
          'quando quiser.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
            child: const Text('Sim, cancelar'),
          ),
        ],
      ),
    );
    if (mounted) {
      setState(() => _abrindoConfirmacaoCancelarChamada.remove(pedidoId));
    } else {
      _abrindoConfirmacaoCancelarChamada.remove(pedidoId);
    }
    if (ok != true || !mounted) return;
    setState(() => _cancelandoChamadaEmProgresso.add(pedidoId));

    try {
      final callable = appFirebaseFunctions.httpsCallable(
        'lojistaCancelarChamadaEntregador',
      );
      await callable.call(<String, dynamic>{'pedidoId': pedidoId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Chamada cancelada. Use "Solicitar entregador" para buscar de novo.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[cancelarChamada] Functions: ${e.code} ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Não foi possível cancelar a chamada.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('[cancelarChamada] Erro: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _cancelandoChamadaEmProgresso.remove(pedidoId));
      } else {
        _cancelandoChamadaEmProgresso.remove(pedidoId);
      }
    }
  }

  Future<void> _chamarEntregadorNovamente(
    String pedidoId, {
    String? tipoAnteriorCanonico,
  }) async {
    if (_abrindoConfirmacaoChamarDeNovo.contains(pedidoId) ||
        _chamandoDeNovoEmProgresso.contains(pedidoId)) {
      return;
    }
    if (mounted) {
      setState(() => _abrindoConfirmacaoChamarDeNovo.add(pedidoId));
    }

    String? tipoEscolhido;
    try {
      final aceitos = await _tiposAceitosDaLojaAtual();
      if (!mounted) return;
      if (aceitos.length == 1) {
        tipoEscolhido = aceitos.first;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Chamar entregador novamente?'),
            content: Text(
              'Reinicia a busca do zero para a categoria '
              '${TiposEntrega.rotulo(tipoEscolhido!)}.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Não'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sim, chamar de novo'),
              ),
            ],
          ),
        );
        if (ok != true) {
          return;
        }
      } else if (aceitos.length > 1) {
        final mensagemAnterior = tipoAnteriorCanonico == null
            ? null
            : 'A categoria ${TiposEntrega.rotulo(tipoAnteriorCanonico)} '
                  'esgotou sem aceite. Tente outra.';
        tipoEscolhido = await EscolherTipoEntregaDialog.mostrar(
          context,
          tiposDisponiveis: aceitos,
          tipoAnteriorMensagem: mensagemAnterior,
        );
        if (tipoEscolhido == null) {
          return;
        }
      } else {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Chamar entregador novamente?'),
            content: const Text(
              'Reinicia a busca do zero: ofertas na ordem de proximidade '
              '(até 3 km, depois 5 km, com expansão gradual; se não houver ninguém, segue a fila).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Não'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sim, chamar de novo'),
              ),
            ],
          ),
        );
        if (ok != true) {
          return;
        }
      }
    } finally {
      if (mounted) {
        setState(() => _abrindoConfirmacaoChamarDeNovo.remove(pedidoId));
      } else {
        _abrindoConfirmacaoChamarDeNovo.remove(pedidoId);
      }
    }
    if (!mounted) return;
    setState(() => _chamandoDeNovoEmProgresso.add(pedidoId));

    try {
      await _redespacharEntregadorViaFirestore(
        pedidoId,
        tipoEntregaSolicitado: tipoEscolhido,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Busca reiniciada. Os entregadores serão chamados novamente.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('[redespachar] Erro: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _chamandoDeNovoEmProgresso.remove(pedidoId));
      } else {
        _chamandoDeNovoEmProgresso.remove(pedidoId);
      }
    }
  }

  /// Redespacho via Firestore: aborta job em andamento, reseta para em_preparo,
  /// depois muda para aguardando_entregador — trigger reconhece a transição.
  Future<void> _redespacharEntregadorViaFirestore(
    String pedidoId, {
    String? tipoEntregaSolicitado,
  }) async {
    final ref = FirebaseFirestore.instance.collection('pedidos').doc(pedidoId);

    final snap = await ref.get();
    if (!snap.exists) throw Exception('Pedido não encontrado.');
    final d = snap.data()!;
    if (d['entregador_id'] != null &&
        d['entregador_id'].toString().isNotEmpty) {
      throw Exception('Já há entregador atribuído.');
    }

    if (d['despacho_job_lock'] != null) {
      await ref.update({'despacho_abort_flag': true});
      for (var i = 0; i < 16; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final cur = await ref.get();
        if (cur.data()?['despacho_job_lock'] == null) break;
      }
    }

    await ref.update(<String, dynamic>{
      'status': PedidoStatus.emPreparo,
      'despacho_job_lock': FieldValue.delete(),
      'despacho_abort_flag': FieldValue.delete(),
      'despacho_fila_ids': <String>[],
      'despacho_indice_atual': 0,
      'despacho_recusados': <String>[],
      'despacho_bloqueados': <String>[],
      'despacho_oferta_uid': FieldValue.delete(),
      'despacho_oferta_expira_em': FieldValue.delete(),
      'despacho_oferta_seq': 0,
      'despacho_oferta_estado': FieldValue.delete(),
      'despacho_estado': FieldValue.delete(),
      'despacho_sem_entregadores': FieldValue.delete(),
      'despacho_redespacho_loja_em': FieldValue.delete(),
      'despacho_redespacho_entregador_em': FieldValue.delete(),
      'despacho_redirecionado_para_proximo': FieldValue.delete(),
      'despacho_erro_msg': FieldValue.delete(),
      'despacho_aguarda_decisao_lojista': FieldValue.delete(),
      'despacho_macro_ciclo_atual': FieldValue.delete(),
      'despacho_msg_busca_entregador': FieldValue.delete(),
      'despacho_busca_extensao_usada': FieldValue.delete(),
      'despacho_auto_encerrada_sem_entregador': FieldValue.delete(),
      'busca_entregadores_notificados': <String>[],
      'busca_raio_km': FieldValue.delete(),
      'busca_entregador_inicio': FieldValue.delete(),
    });

    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _solicitarEntregadorViaFirestore(
      pedidoId,
      tipoEntregaSolicitado: tipoEntregaSolicitado,
    );
  }

  /// Muda status para `aguardando_entregador` via Firestore direto.
  /// O trigger `notificarEntregadoresPedidoPronto` (Cloud Function) detecta a
  /// transição e executa o despacho sequencial por proximidade server-side.
  ///
  /// [tipoEntregaSolicitado] é obrigatório em lojas com >1 tipo aceito.
  /// Para lojas com 1 único tipo, pode vir nulo/empty — o backend deriva
  /// automaticamente.
  Future<void> _solicitarEntregadorViaFirestore(
    String pedidoId, {
    String? tipoEntregaSolicitado,
  }) async {
    final ref = FirebaseFirestore.instance.collection('pedidos').doc(pedidoId);
    final canon = TiposEntrega.normalizarTipoSolicitado(tipoEntregaSolicitado);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      if (!snap.exists) throw Exception('Pedido não encontrado.');
      final d = snap.data()!;
      if (d['status'] != PedidoStatus.emPreparo) {
        throw Exception('O pedido não está mais em preparo. Atualize a tela.');
      }
      if (d['entregador_id'] != null &&
          d['entregador_id'].toString().isNotEmpty) {
        throw Exception('Já há entregador atribuído.');
      }
      transaction.update(ref, <String, dynamic>{
        'status': PedidoStatus.aguardandoEntregador,
        if (canon.isNotEmpty) 'tipo_entrega_solicitado': canon,
        if (canon.isNotEmpty)
          'tipo_entrega_solicitado_origem': 'lojista_mobile',
        if (canon.isNotEmpty)
          'tipo_entrega_solicitado_em': FieldValue.serverTimestamp(),
        'busca_raio_km': 0.5,
        'busca_entregador_inicio': FieldValue.serverTimestamp(),
        'busca_entregadores_notificados': <String>[],
        'despacho_job_lock': FieldValue.delete(),
        'despacho_abort_flag': FieldValue.delete(),
        'despacho_fila_ids': <String>[],
        'despacho_indice_atual': 0,
        'despacho_recusados': <String>[],
        'despacho_bloqueados': <String>[],
        'despacho_oferta_uid': FieldValue.delete(),
        'despacho_oferta_expira_em': FieldValue.delete(),
        'despacho_oferta_seq': 0,
        'despacho_oferta_estado': FieldValue.delete(),
        'despacho_estado': FieldValue.delete(),
        'despacho_sem_entregadores': FieldValue.delete(),
        'despacho_redespacho_loja_em': FieldValue.delete(),
        'despacho_redespacho_entregador_em': FieldValue.delete(),
        'despacho_redirecionado_para_proximo': FieldValue.delete(),
        'despacho_erro_msg': FieldValue.delete(),
        'despacho_aguarda_decisao_lojista': FieldValue.delete(),
        'despacho_macro_ciclo_atual': FieldValue.delete(),
        'despacho_msg_busca_entregador': FieldValue.delete(),
        'despacho_busca_extensao_usada': FieldValue.delete(),
        'despacho_auto_encerrada_sem_entregador': FieldValue.delete(),
        'despacho_motivo_reversao': FieldValue.delete(),
      });
    });
  }

  /// Resolve a lista de tipos de entrega aceitos pela loja autenticada
  /// lendo primeiro `lojas_public` (fonte pública + allowlist) e caindo em
  /// `users/{uid}` se necessário. Retorna lista normalizada (pode ser vazia
  /// para lojas legado sem config).
  Future<List<String>> _tiposAceitosDaLojaAtual() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return const <String>[];
    try {
      final pub = await FirebaseFirestore.instance
          .collection('lojas_public')
          .doc(uid)
          .get();
      final tiposPub = TiposEntrega.lerDeDoc(pub.data());
      if (tiposPub.isNotEmpty) return tiposPub;
    } catch (e) {
      debugPrint('[solicitarEntregador] lojas_public: $e');
    }
    try {
      final priv = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      return TiposEntrega.lerDeDoc(priv.data());
    } catch (e) {
      debugPrint('[solicitarEntregador] users: $e');
      return const <String>[];
    }
  }

  Future<void> _continuarBuscaEntregadoresCallable(String pedidoId) async {
    if (_continuarBuscaEntregadorEmProgresso) return;
    setState(() => _continuarBuscaEntregadorEmProgresso = true);
    try {
      final callable = appFirebaseFunctions.httpsCallable(
        'lojistaContinuarBuscaEntregadores',
      );
      await callable.call(<String, dynamic>{'pedidoId': pedidoId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Buscando de novo (até 5 rodadas). Aguarde as ofertas aos entregadores.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Não foi possível continuar a busca.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _continuarBuscaEntregadorEmProgresso = false);
      }
    }
  }

  Future<void> _solicitarEntregador(String pedidoId) async {
    if (_solicitandoEntregadorEmProgresso.contains(pedidoId)) return;
    if (mounted) {
      setState(() {
        _solicitandoEntregadorEmProgresso.add(pedidoId);
      });
    }
    try {
      final aceitos = await _tiposAceitosDaLojaAtual();
      String? tipo;
      if (aceitos.length == 1) {
        tipo = aceitos.first;
      } else if (aceitos.length > 1) {
        if (!mounted) return;
        tipo = await EscolherTipoEntregaDialog.mostrar(
          context,
          tiposDisponiveis: aceitos,
        );
        if (tipo == null) {
          return;
        }
      }

      await _solicitarEntregadorViaFirestore(
        pedidoId,
        tipoEntregaSolicitado: tipo,
      );
      if (mounted) {
        final rotuloCategoria = tipo == null
            ? ''
            : ' (${TiposEntrega.rotulo(tipo)})';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Buscando entregador próximo$rotuloCategoria. Você será avisado quando alguém aceitar.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('[solicitarEntregador] Erro: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _solicitandoEntregadorEmProgresso.remove(pedidoId);
        });
      } else {
        _solicitandoEntregadorEmProgresso.remove(pedidoId);
      }
    }
  }

  Future<void> _atualizarStatusPedido(
    String pedidoId,
    String novoStatus,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('pedidos')
          .doc(pedidoId)
          .update({'status': novoStatus});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemStatusAtualizado(novoStatus)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _mensagemStatusAtualizado(String status) {
    switch (status) {
      case PedidoStatus.aceito:
        return 'Pedido aceito.';
      case PedidoStatus.emPreparo:
        return 'Preparo iniciado.';
      case PedidoStatus.aguardandoEntregador:
        return 'Buscando entregador parceiro.';
      case PedidoStatus.aCaminho:
      case PedidoStatus.pronto:
        return 'Status atualizado.';
      case PedidoStatus.entregue:
        return 'Pedido concluído.';
      case PedidoStatus.cancelado:
        return 'Pedido recusado.';
      default:
        return 'Pedido atualizado.';
    }
  }

  Widget _painelDadosEntregador(Map<String, dynamic> pedido) {
    final nome = pedido['entregador_nome']?.toString() ?? 'Entregador';
    final tel = pedido['entregador_telefone']?.toString() ?? '';
    final veiculo = pedido['entregador_veiculo']?.toString() ?? '';
    final foto = pedido['entregador_foto_url']?.toString() ?? '';
    final audicao =
        pedido['entregador_acessibilidade_audicao']?.toString() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            diPertinRoxo.withValues(alpha: 0.08),
            diPertinRoxo.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: diPertinRoxo.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: diPertinRoxo,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'ENTREGADOR PARCEIRO',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontSize: 9.5,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                    color: diPertinRoxo.withValues(alpha: 0.3),
                    width: 2,
                  ),
                  image: foto.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(foto),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: foto.isEmpty
                    ? const Icon(
                        Icons.delivery_dining_rounded,
                        color: diPertinRoxo,
                        size: 28,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                        color: _tintaForte,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (tel.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.phone_rounded,
                            size: 13,
                            color: _tintaMedia,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            tel,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: _tintaMedia,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (veiculo.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.two_wheeler_rounded,
                            size: 13,
                            color: _tintaMedia,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            veiculo,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: _tintaMedia,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          BadgeEntregadorAcessibilidade(audicao: audicao),
        ],
      ),
    );
  }

  Widget? _painelMotivoCancelamentoCliente(Map<String, dynamic> pedido) {
    if (pedido['status'] != PedidoStatus.cancelado) return null;
    if (pedido['cancelado_motivo']?.toString() !=
        PedidoStatus.canceladoMotivoClienteSolicitou) {
      return null;
    }
    final cod = pedido['cancelado_cliente_codigo']?.toString().trim() ?? '';
    final det = pedido['cancelado_cliente_detalhe']?.toString().trim() ?? '';
    String linha;
    switch (cod) {
      case PedidoStatus.cancelClienteCodDesistencia:
        linha = 'Cliente desistiu do pedido.';
        break;
      case PedidoStatus.cancelClienteCodDemoraLoja:
        linha = 'Motivo: a loja está demorando para o envio.';
        break;
      case PedidoStatus.cancelClienteCodOutro:
        linha = det.isEmpty ? 'Outro motivo informado pelo cliente.' : det;
        break;
      default:
        linha = 'Cancelamento solicitado pelo cliente.';
    }
    return _blocoAviso(
      cor: _vermelhoPerigo,
      fundo: const Color(0xFFFFF1F2),
      borda: const Color(0xFFFBD5D8),
      icone: Icons.info_outline_rounded,
      titulo: 'Cancelado pelo cliente',
      mensagem: linha,
    );
  }

  /// Bloco de aviso refinado — usa paleta de tinta consistente (não shade50/400 cru).
  Widget _blocoAviso({
    required Color cor,
    required Color fundo,
    required Color borda,
    required IconData icone,
    String? titulo,
    required String mensagem,
    Widget? acaoInferior,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icone, color: cor, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (titulo != null) ...[
                      Text(
                        titulo,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: cor,
                          fontSize: 13,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                    ],
                    Text(
                      mensagem,
                      style: const TextStyle(
                        color: _tintaForte,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (acaoInferior != null) ...[
            const SizedBox(height: 12),
            acaoInferior,
          ],
        ],
      ),
    );
  }

  String _rotuloStatusLojista(String status, bool isRetirada) {
    switch (status) {
      case PedidoStatus.pendente:
        return 'Pedido recebido';
      case PedidoStatus.aceito:
        return 'Pedido aceito';
      case PedidoStatus.emPreparo:
        return 'Preparando pedido';
      case PedidoStatus.aguardandoEntregador:
        return 'Aguardando entregador';
      case PedidoStatus.entregadorIndoLoja:
        return 'Entregador a caminho da loja';
      case PedidoStatus.saiuEntrega:
      case PedidoStatus.emRota:
        return 'Saiu para entrega';
      case PedidoStatus.aCaminho:
        return isRetirada ? 'Aguardando' : 'Aguardando entregador';
      case PedidoStatus.pronto:
        return 'Pronto para retirada';
      case PedidoStatus.entregue:
        return 'Entregue';
      case PedidoStatus.cancelado:
        return 'Cancelado';
      default:
        return status;
    }
  }

  String _formatarData(Timestamp? timestamp) {
    if (timestamp == null) return 'Agora';
    final DateTime data = timestamp.toDate();
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')} '
        'às ${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}';
  }

  String _rotuloPedido(String id) {
    if (id.length <= 5) return id.toUpperCase();
    return '#${id.substring(0, 5).toUpperCase()}';
  }

  double _precoItem(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: StreamBuilder<QuerySnapshot>(
        stream: _streamPedidosLoja,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return _scaffoldBase(
              body: const Center(
                child: CircularProgressIndicator(color: diPertinRoxo),
              ),
              qtdNovos: 0,
              qtdAndamento: 0,
            );
          }

          if (snapshot.hasError) {
            return _scaffoldBase(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 54,
                        color: _tintaSuave,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Não foi possível carregar os pedidos',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _tintaForte,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _tintaMedia,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              qtdNovos: 0,
              qtdAndamento: 0,
            );
          }

          final todosPedidos = snapshot.data?.docs.toList() ?? [];
          todosPedidos.sort((a, b) {
            final Timestamp? tA = (a.data() as Map)['data_pedido'];
            final Timestamp? tB = (b.data() as Map)['data_pedido'];
            if (tA == null || tB == null) return 0;
            return tB.compareTo(tA);
          });

          final qtdNovos = todosPedidos
              .where((p) => (p.data() as Map)['status'] == 'pendente')
              .length;
          final qtdAndamento = todosPedidos
              .where(
                (p) => PedidoStatus.andamentoLojista.contains(
                  (p.data() as Map)['status'],
                ),
              )
              .length;

          final novos = todosPedidos
              .where((p) => (p.data() as Map)['status'] == 'pendente')
              .toList();

          final andamento = todosPedidos
              .where(
                (p) => PedidoStatus.andamentoLojista.contains(
                  (p.data() as Map)['status'],
                ),
              )
              .toList();

          final historico = todosPedidos
              .where(
                (p) => [
                  'entregue',
                  'cancelado',
                ].contains((p.data() as Map)['status']),
              )
              .toList();

          // Único TabBarView — `_buildListaPedidos` já renderiza o estado
          // vazio por aba, então não precisa alternar o widget-raiz. Isso
          // evita o TabController perder sincronia no rebuild que acontece
          // assim que o Firestore passa de 0 → 1 pedido (momento em que o
          // widget-raiz trocava e a aba "Novos" ficava em branco).
          return _scaffoldBase(
            qtdNovos: qtdNovos,
            qtdAndamento: qtdAndamento,
            body: TabBarView(
              children: [
                _buildListaPedidos(
                  novos,
                  'Nenhum pedido novo no momento.',
                  iconeVazio: Icons.notifications_none_rounded,
                ),
                _buildListaPedidos(
                  andamento,
                  'Nenhum pedido em andamento.',
                  iconeVazio: Icons.soup_kitchen_rounded,
                ),
                _buildListaPedidos(
                  historico,
                  'Histórico vazio.',
                  iconeVazio: Icons.history_rounded,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _scaffoldBase({
    required Widget body,
    required int qtdNovos,
    required int qtdAndamento,
  }) {
    return Scaffold(
      backgroundColor: _fundoTela,
      appBar: AppBar(
        title: const Text(
          'Gestão de pedidos',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            fontSize: 17,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_diPertinRoxoEscuro, diPertinRoxo],
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(66),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_diPertinRoxoEscuro, diPertinRoxo],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: _TabBarPremium(
              tabs: [
                _AbaPremiumConfig(
                  icone: Icons.notifications_active_rounded,
                  titulo: 'Novos',
                  quantidade: qtdNovos,
                  destaque: qtdNovos > 0,
                ),
                _AbaPremiumConfig(
                  icone: Icons.soup_kitchen_rounded,
                  titulo: 'Andamento',
                  quantidade: qtdAndamento,
                ),
                const _AbaPremiumConfig(
                  icone: Icons.history_rounded,
                  titulo: 'Histórico',
                ),
              ],
            ),
          ),
        ),
      ),
      // O Scaffold mede o AppBar automaticamente; não precisamos de
      // `extendBodyBehindAppBar` + Padding manual — essa combinação quando
      // junta com TabBarView + `MediaQuery.of(context)` mudando (teclado,
      // rotação) às vezes fica com altura zero e esconde a lista toda.
      body: body,
    );
  }

  Widget _buildEstadoVazioGeral({
    required String titulo,
    required String subtitulo,
    required IconData icone,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    diPertinRoxo.withValues(alpha: 0.10),
                    diPertinLaranja.withValues(alpha: 0.08),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icone, size: 40, color: diPertinRoxo),
            ),
            const SizedBox(height: 18),
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _tintaForte,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: _tintaMedia,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListaPedidos(
    List<QueryDocumentSnapshot> pedidos,
    String mensagemVazia, {
    required IconData iconeVazio,
  }) {
    if (pedidos.isEmpty) {
      return _buildEstadoVazioGeral(
        titulo: mensagemVazia,
        subtitulo: 'Quando houver algo nesta aba, o card aparece aqui.',
        icone: iconeVazio,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: pedidos.length,
      itemBuilder: (context, index) {
        try {
          final rawData = pedidos[index].data();
          if (rawData is! Map) {
            return const SizedBox.shrink();
          }
          final pedido = Map<String, dynamic>.from(rawData);
          final String id = pedidos[index].id;
          final String status = (pedido['status'] ?? 'pendente').toString();
          final bool isRetirada = pedido['tipo_entrega'] == 'retirada';

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _cardPedido(
              pedido: pedido,
              id: id,
              status: status,
              isRetirada: isRetirada,
            ),
          );
        } catch (e, st) {
          debugPrint('Erro ao renderizar pedido #$index: $e\n$st');
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              'Erro ao exibir pedido: $e',
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          );
        }
      },
    );
  }

  Widget _cardPedido({
    required Map<String, dynamic> pedido,
    required String id,
    required String status,
    required bool isRetirada,
  }) {
    final paleta = _paletaStatus(status);
    final List<dynamic> itens = pedido['itens'] ?? [];
    final Widget? painelMotivoCliente = _painelMotivoCancelamentoCliente(
      pedido,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _bordaSuave),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1530).withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      // IntrinsicHeight é necessário para que `CrossAxisAlignment.stretch`
      // consiga esticar a faixa lateral colorida do mesmo tamanho do card
      // quando o pai é um ListView (altura 0..∞). Sem ele, o Row falha com
      // "RenderBox was not laid out" e a lista inteira fica invisível.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Faixa lateral colorida por status — identificação instantânea.
            Container(width: 4, color: paleta.principal),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _headerPedido(id, pedido, status, isRetirada),
                  const SizedBox(height: 14),
                  _cabecalhoClientePedido(pedido),
                  const SizedBox(height: 12),
                  _pillEntrega(isRetirada, pedido),
                  const SizedBox(height: 14),
                  _listaItensRefinada(itens),
                  const SizedBox(height: 14),
                  if (_podeVerFinanceiro) ...[
                    _caixaFinanceira(pedido, isRetirada),
                    const SizedBox(height: 14),
                  ] else
                    _avisoFinanceiroOculto(isRetirada),
                  if (painelMotivoCliente != null) ...[
                    painelMotivoCliente,
                    const SizedBox(height: 12),
                  ],
                  ChatPedidoBotao(
                    pedidoId: id,
                    lojaId: _uid,
                    lojaNome: (pedido['loja_nome'] ?? '').toString(),
                    tituloOverride: () {
                      final n =
                          (pedido['cliente_nome'] ?? '').toString().trim();
                      return n.isNotEmpty ? n : 'Cliente';
                    }(),
                    subtituloOverride: 'Pedido ${_rotuloPedido(id)}',
                    rotuloAtivo: 'Chat com o cliente',
                    rotuloEncerrado: 'Ver conversa do pedido',
                    encerrado: status == PedidoStatus.entregue ||
                        status == PedidoStatus.cancelado,
                  ),
                  const SizedBox(height: 12),
                  if (pedido['entregador_id'] != null &&
                      pedido['entregador_id'].toString().isNotEmpty &&
                      !isRetirada) ...[
                    _painelDadosEntregador(pedido),
                    const SizedBox(height: 12),
                  ],
                  _acoesPorStatus(id, status, isRetirada, pedido),
                ],
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _headerPedido(
    String id,
    Map<String, dynamic> pedido,
    String status,
    bool isRetirada,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Pedido ${_rotuloPedido(id)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: _tintaForte,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: _tintaSuave,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _tempoRelativo(pedido['data_pedido']),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _tintaMedia,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _formatarData(pedido['data_pedido']),
                style: const TextStyle(
                  color: _tintaSuave,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _chipStatusPedido(status, isRetirada),
      ],
    );
  }

  Widget _listaItensRefinada(List<dynamic> itens) {
    if (itens.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ITENS',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: _tintaSuave,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        ...List.generate(itens.length, (i) {
          final item = itens[i];
          if (item is! Map) return const SizedBox.shrink();
          final map = Map<String, dynamic>.from(item);
          final nome = map['nome']?.toString() ?? '';
          final qtd = map['quantidade'] ?? 1;
          final preco = _precoItem(map['preco']);
          return Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: _fundoTela,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${qtd}x',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      color: _tintaForte,
                      fontFeatures: _numerosTabulares,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    nome,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: _tintaForte,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Mostra preço do item apenas para quem pode ver financeiro
                if (_podeVerFinanceiro)
                  Text(
                    'R\$ ${preco.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _tintaMedia,
                      fontFeatures: _numerosTabulares,
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  /// Caixa financeira premium (Fase 3) — visível apenas para dono + colaborador III.
  Widget _caixaFinanceira(Map<String, dynamic> pedido, bool isRetirada) {
    final double subtotal = (pedido['subtotal'] ?? 0.0).toDouble();
    final String formaPagamentoBruto = (pedido['forma_pagamento'] ??
            pedido['metodo_pagamento'] ??
            pedido['pagamento_metodo'] ??
            pedido['formaPagamento'] ??
            '')
        .toString()
        .trim();
    final String formaPagamentoNormalizada = formaPagamentoBruto.toLowerCase();
    final String formaPagamentoExibicao = formaPagamentoNormalizada == 'dinheiro'
        ? 'Dinheiro'
        : formaPagamentoNormalizada == 'pix'
            ? 'PIX'
            : formaPagamentoBruto;
    final double taxaPlataforma = (pedido['taxa_plataforma'] ?? 0.0).toDouble();
    final double? liquidoSrv = pedido['valor_liquido_lojista'] != null
        ? (pedido['valor_liquido_lojista'] as num).toDouble()
        : null;
    final double seuRecebimento = liquidoSrv ?? subtotal;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _fundoTela,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _bordaSuave),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_rounded,
                size: 15,
                color: _tintaMedia,
              ),
              const SizedBox(width: 6),
              const Text(
                'RESUMO FINANCEIRO',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: _tintaSuave,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _bordaSuave),
                ),
                child: Text(
                  isRetirada ? 'Retirada' : 'Entrega',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _tintaMedia,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _linhaFinanceira(
            rotulo: 'Produtos',
            valor: 'R\$ ${subtotal.toStringAsFixed(2)}',
            corRotulo: _tintaMedia,
            corValor: _tintaForte,
          ),
          if (formaPagamentoExibicao.isNotEmpty) ...[
            const SizedBox(height: 6),
            _linhaFinanceira(
              rotulo: 'Pagamento',
              valor: formaPagamentoExibicao,
              corRotulo: _tintaMedia,
              corValor: _tintaForte,
            ),
          ],
          if (taxaPlataforma > 0) ...[
            const SizedBox(height: 6),
            _linhaFinanceira(
              rotulo: 'Taxa da plataforma',
              valor: '- R\$ ${taxaPlataforma.toStringAsFixed(2)}',
              corRotulo: diPertinRoxo,
              corValor: diPertinRoxo,
            ),
          ],
          if (formaPagamentoNormalizada == 'dinheiro') ...[
            const SizedBox(height: 10),
            _blocoAviso(
              cor: _ambarAviso,
              fundo: const Color(0xFFFFF8E1),
              borda: const Color(0xFFF1D583),
              icone: Icons.payments_rounded,
              mensagem:
                  'Cliente vai pagar em dinheiro ao entregador. Você não precisa preparar troco — quem leva o dinheiro e devolve o troco é o entregador.',
            ),
          ],
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: _bordaSuave,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(
                child: Text(
                  'Você recebe',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _tintaForte,
                    fontSize: 13.5,
                  ),
                ),
              ),
              Text(
                'R\$ ${seuRecebimento.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  color: _verdeSucesso,
                  letterSpacing: -0.6,
                  fontFeatures: _numerosTabulares,
                  height: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _linhaFinanceira({
    required String rotulo,
    required String valor,
    required Color corRotulo,
    required Color corValor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          rotulo,
          style: TextStyle(
            color: corRotulo,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          valor,
          style: TextStyle(
            color: corValor,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFeatures: _numerosTabulares,
          ),
        ),
      ],
    );
  }

  /// Nota discreta para operadores (nível 1-2) que não veem valores financeiros.
  Widget _avisoFinanceiroOculto(bool isRetirada) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _fundoTela,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _bordaSuave),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            color: _tintaSuave,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isRetirada
                  ? 'Modo: retirada. Dados financeiros visíveis apenas para o proprietário.'
                  : 'Modo: entrega. Dados financeiros visíveis apenas para o proprietário.',
              style: const TextStyle(
                fontSize: 11.5,
                color: _tintaMedia,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  //  FASE 4 — AÇÕES POR STATUS (botões padronizados + banners refinados)
  // =========================================================================

  Widget _acoesPorStatus(
    String id,
    String status,
    bool isRetirada,
    Map<String, dynamic> pedido,
  ) {
    if (status == PedidoStatus.pendente) {
      return Row(
        children: [
          Expanded(
            child: _botaoSecundario(
              rotulo: 'Recusar',
              icone: Icons.close_rounded,
              corTexto: _vermelhoPerigo,
              corBorda: _vermelhoPerigo.withValues(alpha: 0.7),
              onPressed: () =>
                  _atualizarStatusPedido(id, PedidoStatus.cancelado),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _botaoPrimario(
              rotulo: 'Aceitar pedido',
              icone: Icons.check_rounded,
              cor: _verdeSucesso,
              onPressed: () =>
                  _atualizarStatusPedido(id, PedidoStatus.aceito),
            ),
          ),
        ],
      );
    }

    if (status == PedidoStatus.aceito) {
      return _botaoPrimario(
        rotulo: 'Iniciar preparo',
        icone: Icons.soup_kitchen_rounded,
        cor: diPertinLaranja,
        onPressed: () =>
            _atualizarStatusPedido(id, PedidoStatus.emPreparo),
      );
    }

    if (status == PedidoStatus.emPreparo) {
      final bool encerrouSemEntregador = !isRetirada &&
          pedido['despacho_auto_encerrada_sem_entregador'] == true;
      final bool carregando =
          _solicitandoEntregadorEmProgresso.contains(id);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (encerrouSemEntregador) ...[
            _blocoAviso(
              cor: _ambarAviso,
              fundo: const Color(0xFFFFF8E1),
              borda: const Color(0xFFF1D583),
              icone: Icons.info_outline_rounded,
              titulo: 'Busca encerrada',
              mensagem: (pedido['despacho_msg_busca_entregador']
                              ?.toString() ??
                          '')
                      .trim()
                      .isNotEmpty
                  ? pedido['despacho_msg_busca_entregador'].toString()
                  : 'A busca por entregador encerrou automaticamente após várias tentativas. Toque em «Solicitar entregador» para tentar de novo.',
            ),
            const SizedBox(height: 10),
          ],
          _botaoPrimario(
            rotulo: isRetirada
                ? 'Pronto para retirada'
                : carregando
                    ? 'Solicitando entregador...'
                    : 'Solicitar entregador',
            icone: isRetirada
                ? Icons.storefront_rounded
                : Icons.two_wheeler_rounded,
            cor: diPertinLaranja,
            carregando: !isRetirada && carregando,
            onPressed: isRetirada
                ? () => _atualizarStatusPedido(id, PedidoStatus.pronto)
                : carregando
                    ? null
                    : () => _solicitarEntregador(id),
          ),
        ],
      );
    }

    if (status == PedidoStatus.aguardandoEntregador) {
      if (pedido['despacho_aguarda_decisao_lojista'] == true) {
        return _blocoAviso(
          cor: _ambarAviso,
          fundo: const Color(0xFFFFF8E1),
          borda: const Color(0xFFF1D583),
          icone: Icons.pause_circle_outline_rounded,
          titulo: 'Decidir o que fazer',
          mensagem: (pedido['despacho_msg_busca_entregador']?.toString() ??
                      '')
                  .trim()
                  .isNotEmpty
              ? pedido['despacho_msg_busca_entregador'].toString()
              : 'Ainda não encontramos um entregador após 5 rodadas (3 km e 5 km). Você pode cancelar a chamada ou continuar buscando por mais 5 rodadas.',
          acaoInferior: Row(
            children: [
              Expanded(
                child: _botaoSecundario(
                  rotulo: 'Continuar buscando',
                  icone: Icons.refresh_rounded,
                  corTexto: _tintaForte,
                  corBorda: _bordaSuave,
                  onPressed: _continuarBuscaEntregadorEmProgresso
                      ? null
                      : () => _continuarBuscaEntregadoresCallable(id),
                  carregando: _continuarBuscaEntregadorEmProgresso,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _botaoPrimario(
                  rotulo: _cancelandoChamadaEmProgresso.contains(id)
                      ? 'Cancelando...'
                      : 'Cancelar chamada',
                  icone: Icons.close_rounded,
                  cor: _vermelhoPerigo,
                  carregando:
                      _cancelandoChamadaEmProgresso.contains(id),
                  onPressed:
                      (_abrindoConfirmacaoCancelarChamada.contains(id) ||
                              _cancelandoChamadaEmProgresso
                                  .contains(id))
                          ? null
                          : () => _cancelarChamadaEntregador(id),
                ),
              ),
            ],
          ),
        );
      }

      final String msgBusca = pedido['despacho_busca_extensao_usada'] == true
          ? 'Buscando de novo: até 5 rodadas (3 km, depois 5 km). Se ninguém aceitar, a chamada encerra e o pedido volta para «Em preparo».'
          : 'Buscando entregador: até 5 rodadas começando pelos mais próximos (até 3 km, depois 5 km). Se ninguém aceitar, você poderá continuar ou cancelar.';

      final String? rodada = pedido['despacho_macro_ciclo_atual'] != null
          ? 'Rodada ${pedido['despacho_macro_ciclo_atual']}/'
              '${pedido['despacho_busca_extensao_usada'] == true ? '5 (extra)' : '5'}'
          : null;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _blocoAviso(
            cor: _azulInfo,
            fundo: const Color(0xFFEFF5FE),
            borda: const Color(0xFFC8DAF9),
            icone: Icons.radar_rounded,
            titulo: rodada ?? 'Buscando entregador',
            mensagem: msgBusca,
          ),
          const SizedBox(height: 10),
          _botaoSecundario(
            rotulo: _cancelandoChamadaEmProgresso.contains(id)
                ? 'Cancelando...'
                : 'Cancelar chamada',
            icone: Icons.close_rounded,
            corTexto: _azulInfo,
            corBorda: _azulInfo.withValues(alpha: 0.5),
            carregando: _cancelandoChamadaEmProgresso.contains(id),
            onPressed: (_abrindoConfirmacaoCancelarChamada.contains(id) ||
                    _cancelandoChamadaEmProgresso.contains(id))
                ? null
                : () => _cancelarChamadaEntregador(id),
          ),
          const SizedBox(height: 8),
          _botaoSecundario(
            rotulo: _chamandoDeNovoEmProgresso.contains(id)
                ? 'Reiniciando busca...'
                : 'Chamar de novo',
            icone: Icons.refresh_rounded,
            corTexto: diPertinLaranja,
            corBorda: diPertinLaranja.withValues(alpha: 0.7),
            carregando: _chamandoDeNovoEmProgresso.contains(id),
            onPressed: (_abrindoConfirmacaoChamarDeNovo.contains(id) ||
                    _chamandoDeNovoEmProgresso.contains(id))
                ? null
                : () => _chamarEntregadorNovamente(
                      id,
                      tipoAnteriorCanonico:
                          TiposEntrega.normalizarTipoSolicitado(
                            pedido['tipo_entrega_solicitado'],
                          ).isNotEmpty
                          ? TiposEntrega.normalizarTipoSolicitado(
                              pedido['tipo_entrega_solicitado'],
                            )
                          : null,
                    ),
          ),
        ],
      );
    }

    if (isRetirada && status == PedidoStatus.pronto) {
      return _botaoPrimario(
        rotulo: 'Confirmar retirada no balcão',
        icone: Icons.task_alt_rounded,
        cor: _verdeSucesso,
        onPressed: () =>
            _atualizarStatusPedido(id, PedidoStatus.entregue),
      );
    }

    final bool emRota = !isRetirada &&
        (status == PedidoStatus.aCaminho ||
            status == PedidoStatus.emRota ||
            status == PedidoStatus.saiuEntrega ||
            status == PedidoStatus.entregadorIndoLoja);

    if (emRota) {
      final bool semEntregadorVinculado = pedido['entregador_id'] == null ||
          pedido['entregador_id'].toString().isEmpty;
      if (semEntregadorVinculado) {
        return _blocoTokenEntrega(id, pedido);
      }
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 14,
              color: _tintaSuave,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Acompanhe a entrega pelo app do entregador.',
                style: TextStyle(
                  fontSize: 12,
                  color: _tintaMedia,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Fallback para status terminais: entregue/cancelado/desconhecido.
    return const SizedBox.shrink();
  }

  Widget _blocoTokenEntrega(String id, Map<String, dynamic> pedido) {
    return _blocoAviso(
      cor: _ambarAviso,
      fundo: const Color(0xFFFFF8E1),
      borda: const Color(0xFFF1D583),
      icone: Icons.vpn_key_rounded,
      titulo: 'Aguardando entregador aceitar',
      mensagem:
          'Se você mesmo entregar com motoboy da loja, digite o token que o cliente informar:',
      acaoInferior: TextField(
        decoration: InputDecoration(
          hintText: 'Token do cliente (6 caracteres)',
          hintStyle: const TextStyle(
            color: _tintaSuave,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _bordaSuave),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _bordaSuave),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: diPertinRoxo, width: 1.5),
          ),
          prefixIcon: const Icon(Icons.key_rounded, color: _tintaMedia, size: 20),
        ),
        style: const TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w800,
          fontSize: 15,
          letterSpacing: 2,
          color: _tintaForte,
        ),
        textCapitalization: TextCapitalization.characters,
        keyboardType: TextInputType.text,
        onSubmitted: (value) async {
          String tokenReal = pedido['token_entrega']?.toString() ?? '';
          if (tokenReal.isEmpty && id.length >= 6) {
            tokenReal = id.substring(id.length - 6).toUpperCase();
          }
          if (value.trim().toUpperCase() == tokenReal.toUpperCase()) {
            _atualizarStatusPedido(id, PedidoStatus.entregue);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Token incorreto.'),
                backgroundColor: _vermelhoPerigo,
              ),
            );
          }
        },
      ),
    );
  }

  // =========================================================================
  //  BOTÕES PADRONIZADOS — primário (FilledButton) e secundário (OutlinedButton)
  // =========================================================================

  Widget _botaoPrimario({
    required String rotulo,
    required IconData icone,
    required Color cor,
    required VoidCallback? onPressed,
    bool carregando = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: cor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: cor.withValues(alpha: 0.5),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (carregando)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            else
              Icon(icone, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                rotulo,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _botaoSecundario({
    required String rotulo,
    required IconData icone,
    required Color corTexto,
    required Color corBorda,
    required VoidCallback? onPressed,
    bool carregando = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: corTexto,
          side: BorderSide(color: corBorda, width: 1.2),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (carregando)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(corTexto),
                ),
              )
            else
              Icon(icone, size: 17, color: corTexto),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                rotulo,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: corTexto,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
//  TabBar premium com indicador pill (fora da classe principal)
// ===========================================================================

/// Contador compacto para abas: altura fixa evita “cápsula” vertical alta
/// (comum quando só há um dígito e o [Container] herda altura do [Tab]).
class _ContadorAbaTab extends StatelessWidget {
  final int quantidade;
  final bool destaque;

  const _ContadorAbaTab({
    required this.quantidade,
    this.destaque = false,
  });

  @override
  Widget build(BuildContext context) {
    final texto = quantidade > 99 ? '99+' : '$quantidade';
    final largo = texto.length > 1;
    const altura = 19.0;
    final minLargura = largo ? 26.0 : altura;

    return Container(
      height: altura,
      constraints: BoxConstraints(minWidth: minLargura),
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: largo ? 6 : 0),
      decoration: BoxDecoration(
        color: destaque
            ? Colors.white
            : Colors.white.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(altura / 2),
      ),
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: largo ? 9.5 : 10,
          fontWeight: FontWeight.w800,
          height: 1.0,
          letterSpacing: -0.3,
          color: destaque ? diPertinRoxo : Colors.white,
        ),
      ),
    );
  }
}

class _AbaPremiumConfig {
  final IconData icone;
  final String titulo;
  final int quantidade;
  final bool destaque;

  const _AbaPremiumConfig({
    required this.icone,
    required this.titulo,
    this.quantidade = 0,
    this.destaque = false,
  });
}

class _TabBarPremium extends StatelessWidget {
  final List<_AbaPremiumConfig> tabs;
  const _TabBarPremium({required this.tabs});

  @override
  Widget build(BuildContext context) {
    return TabBar(
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white70,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      dividerColor: Colors.transparent,
      splashBorderRadius: BorderRadius.circular(999),
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.symmetric(vertical: 4),
      tabs: tabs
          .map(
            (t) => Tab(
              height: 40,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(t.icone, size: 17),
                  const SizedBox(width: 6),
                  Text(
                    t.titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: -0.2,
                      height: 1.0,
                    ),
                  ),
                  if (t.quantidade > 0) ...[
                    const SizedBox(width: 5),
                    _ContadorAbaTab(
                      quantidade: t.quantidade,
                      destaque: t.destaque,
                    ),
                  ],
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

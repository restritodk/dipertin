// Arquivo: lib/screens/lojista/lojista_pedidos_screen.dart

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:depertin_cliente/constants/pedido_status.dart';
import 'package:depertin_cliente/services/firebase_functions_config.dart';
import 'package:depertin_cliente/widgets/badge_entregador_acessibilidade.dart';
import 'package:depertin_cliente/widgets/chat_pedido_botao.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class LojistaPedidosScreen extends StatefulWidget {
  const LojistaPedidosScreen({super.key, this.uidLoja});

  final String? uidLoja;

  @override
  State<LojistaPedidosScreen> createState() => _LojistaPedidosScreenState();
}

class _LojistaPedidosScreenState extends State<LojistaPedidosScreen> {
  late final String _uid =
      widget.uidLoja ?? FirebaseAuth.instance.currentUser!.uid;

  late final Stream<QuerySnapshot> _streamPedidosLoja = FirebaseFirestore
      .instance
      .collection('pedidos')
      .where('loja_id', isEqualTo: _uid)
      .snapshots();

  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<QuerySnapshot>? _pedidosSubscription;
  bool _primeiroCarregamento = true;
  bool _continuarBuscaEntregadorEmProgresso = false;
  final Set<String> _solicitandoEntregadorEmProgresso = <String>{};
  final Set<String> _abrindoConfirmacaoCancelarChamada = <String>{};
  final Set<String> _cancelandoChamadaEmProgresso = <String>{};
  final Set<String> _abrindoConfirmacaoChamarDeNovo = <String>{};
  final Set<String> _chamandoDeNovoEmProgresso = <String>{};

  @override
  void initState() {
    super.initState();
    _iniciarVigiaDePedidos();
  }

  @override
  void dispose() {
    _pedidosSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  /// Foto + nome do cliente denormalizados no pedido (`cliente_nome` e
  /// `cliente_foto_perfil`, Fase 3G.3). Evita ler `users/{cliente_id}` —
  /// necessário porque a rule de `users` agora bloqueia leitura cruzada entre
  /// autenticados para proteger CPF/email/telefone/saldo de quem não é lojista.
  Widget _cabecalhoClientePedido(Map<String, dynamic> pedido) {
    final nomeGravado = (pedido['cliente_nome'] ?? '').toString().trim();
    final foto = (pedido['cliente_foto_perfil'] ?? '').toString().trim();
    final nome = nomeGravado.isNotEmpty ? nomeGravado : 'Cliente';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.grey.shade300,
            backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
            child: foto.isEmpty
                ? const Icon(Icons.person, color: diPertinRoxo, size: 26)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cliente',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  nome,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
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

  Future<void> _chamarEntregadorNovamente(String pedidoId) async {
    if (_abrindoConfirmacaoChamarDeNovo.contains(pedidoId) ||
        _chamandoDeNovoEmProgresso.contains(pedidoId)) {
      return;
    }
    if (mounted) {
      setState(() => _abrindoConfirmacaoChamarDeNovo.add(pedidoId));
    }
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
    if (mounted) {
      setState(() => _abrindoConfirmacaoChamarDeNovo.remove(pedidoId));
    } else {
      _abrindoConfirmacaoChamarDeNovo.remove(pedidoId);
    }
    if (ok != true || !mounted) return;
    setState(() => _chamandoDeNovoEmProgresso.add(pedidoId));

    try {
      await _redespacharEntregadorViaFirestore(pedidoId);
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
  Future<void> _redespacharEntregadorViaFirestore(String pedidoId) async {
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
    await _solicitarEntregadorViaFirestore(pedidoId);
  }

  /// Muda status para `aguardando_entregador` via Firestore direto.
  /// O trigger `notificarEntregadoresPedidoPronto` (Cloud Function) detecta a
  /// transição e executa o despacho sequencial por proximidade server-side.
  Future<void> _solicitarEntregadorViaFirestore(String pedidoId) async {
    final ref = FirebaseFirestore.instance.collection('pedidos').doc(pedidoId);

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
      });
    });
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
      await _solicitarEntregadorViaFirestore(pedidoId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Buscando entregador próximo. Você será avisado quando alguém aceitar.',
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: diPertinRoxo.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: diPertinRoxo.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Entregador parceiro',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: diPertinRoxo,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.grey.shade300,
                backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
                child: foto.isEmpty
                    ? const Icon(Icons.delivery_dining, color: diPertinRoxo)
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
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (tel.isNotEmpty)
                      Text('Tel. $tel', style: const TextStyle(fontSize: 13)),
                    if (veiculo.isNotEmpty)
                      Text(
                        'Veículo: $veiculo',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
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
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.red.shade800, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cancelado pelo cliente',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.red.shade900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  linha,
                  style: TextStyle(
                    color: Colors.grey.shade900,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
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

  Future<void> _confirmarRetiradaComEstorno(
    String pedidoId,
    String clienteId,
    double taxaEntrega,
  ) async {
    final bool confirmacao =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: const Text(
              'Confirmar retirada?',
              style: TextStyle(color: diPertinLaranja),
            ),
            content: Text(
              'O cliente decidiu vir buscar o pedido?\n\n'
              'Ao confirmar, o valor de R\$ ${taxaEntrega.toStringAsFixed(2)} referente à entrega '
              'será estornado e devolvido para a carteira do cliente no aplicativo.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: diPertinLaranja,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Sim, estornar frete',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmacao) return;

    // Fase 3G.3 — estorno via callable (Admin SDK). Antes o lojista fazia
    // `update users/{cliente_id}.saldo` direto, o que forçava a rule de
    // `users` a permitir escritas cruzadas. Agora a função valida que o
    // caller é a loja do pedido antes de creditar o saldo.
    try {
      final callable = appFirebaseFunctions.httpsCallable(
        'lojistaConfirmarRetiradaNaLojaComEstorno',
      );
      await callable.call(<String, dynamic>{'pedidoId': pedidoId});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pedido finalizado e frete devolvido ao cliente.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Erro ao estornar o frete.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao estornar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
            return Scaffold(
              backgroundColor: Colors.grey[100],
              appBar: AppBar(
                title: const Text(
                  'Gestão de pedidos',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: diPertinLaranja,
                iconTheme: const IconThemeData(color: Colors.white),
              ),
              body: const Center(
                child: CircularProgressIndicator(color: diPertinLaranja),
              ),
            );
          }

          if (snapshot.hasError) {
            return Scaffold(
              backgroundColor: Colors.grey[100],
              appBar: AppBar(
                title: const Text(
                  'Gestão de pedidos',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: diPertinLaranja,
                iconTheme: const IconThemeData(color: Colors.white),
              ),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Não foi possível carregar os pedidos.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
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

          return Scaffold(
            backgroundColor: Colors.grey[100],
            appBar: AppBar(
              title: const Text(
                'Gestão de pedidos',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: diPertinLaranja,
              iconTheme: const IconThemeData(color: Colors.white),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: TabBar(
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.white,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(
                      child: _abaComContador(
                        icone: Icons.notifications_active,
                        titulo: 'Novos',
                        quantidade: qtdNovos,
                        destaque: qtdNovos > 0,
                      ),
                    ),
                    Tab(
                      child: _abaComContador(
                        icone: Icons.soup_kitchen,
                        titulo: 'Andamento',
                        quantidade: qtdAndamento,
                        destaque: false,
                      ),
                    ),
                    const Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history, size: 20),
                          SizedBox(width: 6),
                          Text('Histórico'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            body: todosPedidos.isEmpty
                ? TabBarView(
                    children: [
                      _buildEstadoVazioGeral(),
                      _buildEstadoVazioGeral(),
                      _buildEstadoVazioGeral(),
                    ],
                  )
                : TabBarView(
                    children: [
                      _buildListaPedidos(
                        novos,
                        'Nenhum pedido novo no momento.',
                      ),
                      _buildListaPedidos(
                        andamento,
                        'Nenhum pedido em andamento.',
                      ),
                      _buildListaPedidos(historico, 'Histórico vazio.'),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _abaComContador({
    required IconData icone,
    required String titulo,
    required int quantidade,
    required bool destaque,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: 20),
        const SizedBox(width: 6),
        Text(titulo),
        if (quantidade > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: destaque
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              quantidade > 99 ? '99+' : '$quantidade',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: destaque ? diPertinLaranja : Colors.white,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEstadoVazioGeral() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 72, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Nenhum pedido ainda',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Quando chegar um pedido novo, ele aparece na aba Novos e você ouve um aviso sonoro.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListaPedidos(
    List<QueryDocumentSnapshot> pedidos,
    String mensagemVazia,
  ) {
    if (pedidos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            mensagemVazia,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 15),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: pedidos.length,
      itemBuilder: (context, index) {
        final pedido = pedidos[index].data() as Map<String, dynamic>;
        final String id = pedidos[index].id;
        final String status = pedido['status'] ?? 'pendente';
        final bool isRetirada = pedido['tipo_entrega'] == 'retirada';
        final List<dynamic> itens = pedido['itens'] ?? [];
        final String clienteId = pedido['cliente_id'] ?? '';
        final Widget? painelMotivoCliente = _painelMotivoCancelamentoCliente(
          pedido,
        );

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Pedido ${_rotuloPedido(id)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      _formatarData(pedido['data_pedido']),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
                const Divider(),
                _cabecalhoClientePedido(pedido),
                Row(
                  children: [
                    Icon(
                      isRetirada ? Icons.storefront : Icons.two_wheeler,
                      color: isRetirada ? diPertinLaranja : diPertinRoxo,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isRetirada
                            ? 'Retirada no balcão'
                            : 'Entrega: ${pedido['endereco_entrega']}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isRetirada ? diPertinLaranja : diPertinRoxo,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...itens.map((item) {
                  if (item is! Map) {
                    return const SizedBox.shrink();
                  }
                  final map = Map<String, dynamic>.from(item);
                  final nome = map['nome']?.toString() ?? '';
                  final qtd = map['quantidade'] ?? 1;
                  final preco = _precoItem(map['preco']);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          '${qtd}x ',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Expanded(child: Text(nome)),
                        Text('R\$ ${preco.toStringAsFixed(2)}'),
                      ],
                    ),
                  );
                }),
                const Divider(),
                Builder(
                  builder: (context) {
                    final double subtotal = (pedido['subtotal'] ?? 0.0)
                        .toDouble();
                    final String formaPagamentoBruto =
                        (pedido['forma_pagamento'] ??
                                pedido['metodo_pagamento'] ??
                                pedido['pagamento_metodo'] ??
                                pedido['formaPagamento'] ??
                                '')
                            .toString()
                            .trim();
                    final String formaPagamentoNormalizada = formaPagamentoBruto
                        .toLowerCase();
                    final String formaPagamentoExibicao =
                        formaPagamentoNormalizada == 'dinheiro'
                        ? 'Dinheiro'
                        : formaPagamentoNormalizada == 'pix'
                        ? 'PIX'
                        : formaPagamentoBruto;
                    // Modelo iFood: o entregador é o responsável pelo dinheiro
                    // e pelo troco. O lojista não vê mais "Troco para R$ X" —
                    // apenas o aviso de que o cliente vai pagar em dinheiro
                    // direto ao entregador. Isso evita confusão com o líquido
                    // que o lojista realmente recebe.
                    final double taxaPlataforma =
                        (pedido['taxa_plataforma'] ?? 0.0).toDouble();
                    final double? liquidoSrv =
                        pedido['valor_liquido_lojista'] != null
                        ? (pedido['valor_liquido_lojista'] as num).toDouble()
                        : null;
                    final double seuRecebimento = liquidoSrv ?? subtotal;

                    return Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isRetirada ? 'Modo: retirada' : 'Modo: entrega',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Produtos: R\$ ${subtotal.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                        if (formaPagamentoExibicao.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Pagamento:',
                                  style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  formaPagamentoExibicao,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (formaPagamentoNormalizada == 'dinheiro')
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.amber.withValues(alpha: 0.5),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.payments_outlined,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Cliente vai pagar em dinheiro ao entregador. Você não precisa preparar troco — quem leva o dinheiro e devolve o troco é o entregador.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (taxaPlataforma > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Taxa da plataforma:',
                                  style: TextStyle(
                                    color: Colors.deepPurple,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'R\$ ${taxaPlataforma.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: Colors.deepPurple,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Seu recebimento (líquido):',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            Text(
                              'R\$ ${seuRecebimento.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    label: Text(
                      _rotuloStatusLojista(status, isRetirada),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    backgroundColor: diPertinLaranja.withValues(alpha: 0.2),
                    side: BorderSide(
                      color: diPertinLaranja.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                if (painelMotivoCliente != null) ...[
                  const SizedBox(height: 10),
                  painelMotivoCliente,
                ],
                const SizedBox(height: 12),

                // Chat com o cliente (ou histórico da conversa quando o
                // pedido está encerrado). Fica sempre visível para facilitar
                // o acesso durante o preparo/entrega e permitir revisita
                // pós-entrega.
                ChatPedidoBotao(
                  pedidoId: id,
                  lojaId: _uid,
                  lojaNome: (pedido['loja_nome'] ?? '').toString(),
                  tituloOverride: () {
                    final n = (pedido['cliente_nome'] ?? '').toString().trim();
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
                    !isRetirada)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _painelDadosEntregador(pedido),
                  ),

                if (status == PedidoStatus.pendente)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                          onPressed: () => _atualizarStatusPedido(
                            id,
                            PedidoStatus.cancelado,
                          ),
                          child: const Text('Recusar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                          onPressed: () =>
                              _atualizarStatusPedido(id, PedidoStatus.aceito),
                          child: const Text(
                            'Aceitar pedido',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else if (status == PedidoStatus.aceito)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: diPertinLaranja,
                      ),
                      onPressed: () =>
                          _atualizarStatusPedido(id, PedidoStatus.emPreparo),
                      child: const Text(
                        'Iniciar preparo',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                else if (status == PedidoStatus.emPreparo)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!isRetirada &&
                          pedido['despacho_auto_encerrada_sem_entregador'] ==
                              true) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.shade400),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.amber.shade900,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  (pedido['despacho_msg_busca_entregador']
                                              ?.toString() ??
                                          '')
                                      .trim()
                                      .isNotEmpty
                                      ? pedido['despacho_msg_busca_entregador']
                                          .toString()
                                      : 'A busca por entregador encerrou automaticamente '
                                          'após várias tentativas. Toque em «Solicitar entregador» '
                                          'para tentar de novo.',
                                  style: TextStyle(
                                    color: Colors.grey.shade900,
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: diPertinLaranja,
                          ),
                          onPressed: isRetirada
                              ? () => _atualizarStatusPedido(
                                    id,
                                    PedidoStatus.pronto,
                                  )
                              : _solicitandoEntregadorEmProgresso.contains(id)
                              ? null
                              : () => _solicitarEntregador(id),
                          child: Text(
                            isRetirada
                                ? 'Pronto para retirada'
                                : _solicitandoEntregadorEmProgresso.contains(id)
                                ? 'Solicitando entregador...'
                                : 'Solicitar entregador',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else if (status == PedidoStatus.aguardandoEntregador)
                  pedido['despacho_aguarda_decisao_lojista'] == true
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.shade400),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.pause_circle_outline,
                                    color: Colors.amber.shade900,
                                    size: 26,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      (pedido['despacho_msg_busca_entregador']
                                                  ?.toString() ??
                                              '')
                                          .trim()
                                          .isNotEmpty
                                          ? pedido['despacho_msg_busca_entregador']
                                              .toString()
                                          : 'Ainda não encontramos um entregador após 5 rodadas '
                                              '(3 km e 5 km). Você pode cancelar a chamada ou '
                                              'continuar buscando por mais 5 rodadas.',
                                      style: TextStyle(
                                        color: Colors.grey.shade900,
                                        fontSize: 13,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _continuarBuscaEntregadorEmProgresso
                                          ? null
                                          : () => _continuarBuscaEntregadoresCallable(
                                                id,
                                              ),
                                      child: const Text('Continuar buscando'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.red.shade700,
                                      ),
                                      onPressed:
                                          (_abrindoConfirmacaoCancelarChamada
                                                  .contains(id) ||
                                              _cancelandoChamadaEmProgresso
                                                  .contains(id))
                                          ? null
                                          : () =>
                                                _cancelarChamadaEntregador(id),
                                      child: Text(
                                        _cancelandoChamadaEmProgresso
                                                .contains(id)
                                            ? 'Cancelando...'
                                            : _abrindoConfirmacaoCancelarChamada
                                                  .contains(id)
                                            ? 'Abrindo...'
                                            : 'Cancelar chamada',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      : Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.radar, color: Colors.blue.shade800),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      pedido['despacho_busca_extensao_usada'] ==
                                              true
                                          ? 'Buscando de novo: até 5 rodadas '
                                                '(3 km, depois 5 km). Se ninguém aceitar, '
                                                'a chamada encerra e o pedido volta para «Em preparo».'
                                          : 'Buscando entregador: até 5 rodadas começando pelos '
                                                'mais próximos (até 3 km, depois 5 km). '
                                                'Se ninguém aceitar, você poderá continuar ou cancelar.',
                                      style: TextStyle(
                                        color: Colors.blue.shade900,
                                        fontSize: 13,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (pedido['despacho_macro_ciclo_atual'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Rodada atual: '
                                    '${pedido['despacho_macro_ciclo_atual']}/'
                                    '${pedido['despacho_busca_extensao_usada'] == true ? '5 (extra)' : '5'}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blue.shade800,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed:
                                      (_abrindoConfirmacaoCancelarChamada
                                              .contains(id) ||
                                          _cancelandoChamadaEmProgresso
                                              .contains(id))
                                      ? null
                                      : () => _cancelarChamadaEntregador(id),
                                  icon: Icon(
                                    _cancelandoChamadaEmProgresso.contains(id)
                                        ? Icons.hourglass_top
                                        : Icons.close,
                                    size: 20,
                                  ),
                                  label: Text(
                                    _cancelandoChamadaEmProgresso.contains(id)
                                        ? 'Cancelando...'
                                        : _abrindoConfirmacaoCancelarChamada
                                              .contains(id)
                                        ? 'Abrindo...'
                                        : 'Cancelar chamada',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.blue.shade900,
                                    side: BorderSide(color: Colors.blue.shade400),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed:
                                      (_abrindoConfirmacaoChamarDeNovo
                                              .contains(id) ||
                                          _chamandoDeNovoEmProgresso.contains(
                                            id,
                                          ))
                                      ? null
                                      : () => _chamarEntregadorNovamente(id),
                                  icon: Icon(
                                    _chamandoDeNovoEmProgresso.contains(id) ||
                                            _abrindoConfirmacaoChamarDeNovo
                                                .contains(id)
                                        ? Icons.hourglass_top
                                        : Icons.refresh,
                                    size: 20,
                                  ),
                                  label: Text(
                                    _chamandoDeNovoEmProgresso.contains(id)
                                        ? 'Reiniciando busca...'
                                        : _abrindoConfirmacaoChamarDeNovo
                                              .contains(id)
                                        ? 'Abrindo...'
                                        : 'Chamar de novo',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: diPertinLaranja,
                                    side: BorderSide(
                                      color: diPertinLaranja.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                else if (isRetirada && status == PedidoStatus.pronto)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      onPressed: () =>
                          _atualizarStatusPedido(id, PedidoStatus.entregue),
                      child: const Text(
                        'Confirmar retirada no balcão',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                else if (!isRetirada &&
                    (status == PedidoStatus.aCaminho ||
                        status == PedidoStatus.emRota ||
                        status == PedidoStatus.saiuEntrega ||
                        status == PedidoStatus.entregadorIndoLoja) &&
                    (pedido['entregador_id'] == null ||
                        pedido['entregador_id'].toString().isEmpty))
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber[50],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Aguardando entregador aceitar (fluxo legado ou sem GPS na loja).',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Se você mesmo entregar com motoboy da loja, use o token abaixo.',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          decoration: const InputDecoration(
                            hintText: 'Digite o token do cliente',
                            isDense: true,
                            border: OutlineInputBorder(),
                            fillColor: Colors.white,
                            filled: true,
                          ),
                          textCapitalization: TextCapitalization.characters,
                          keyboardType: TextInputType.text,
                          onSubmitted: (value) async {
                            String tokenReal =
                                pedido['token_entrega']?.toString() ?? '';
                            if (tokenReal.isEmpty && id.length >= 6) {
                              tokenReal = id
                                  .substring(id.length - 6)
                                  .toUpperCase();
                            }
                            if (value.trim().toUpperCase() ==
                                tokenReal.toUpperCase()) {
                              _atualizarStatusPedido(id, PedidoStatus.entregue);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Token incorreto.'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  )
                else if (!isRetirada &&
                    (status == PedidoStatus.aCaminho ||
                        status == PedidoStatus.emRota ||
                        status == PedidoStatus.saiuEntrega ||
                        status == PedidoStatus.entregadorIndoLoja) &&
                    pedido['entregador_id'] != null &&
                    pedido['entregador_id'].toString().isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: Text(
                          'Acompanhe a entrega pelo app do entregador.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          final double taxaEntrega =
                              (pedido['taxa_entrega'] ?? 0.0).toDouble();
                          _confirmarRetiradaComEstorno(
                            id,
                            clienteId,
                            taxaEntrega,
                          );
                        },
                        icon: const Icon(Icons.person_pin_circle_outlined),
                        label: const Text(
                          'Cliente retirou com você no balcão (estornar frete)',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )
                else
                  Center(
                    child: Chip(
                      label: Text(
                        status.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: status == PedidoStatus.entregue
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

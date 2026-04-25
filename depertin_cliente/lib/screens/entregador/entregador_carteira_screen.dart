// Arquivo: lib/screens/entregador/entregador_carteira_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../services/biometria_service.dart';
import '../../services/firebase_functions_config.dart';
import 'package:intl/intl.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class EntregadorCarteiraScreen extends StatefulWidget {
  const EntregadorCarteiraScreen({super.key});

  @override
  State<EntregadorCarteiraScreen> createState() =>
      _EntregadorCarteiraScreenState();
}

class _EntregadorCarteiraScreenState extends State<EntregadorCarteiraScreen> {
  final TextEditingController _chavePixController = TextEditingController();
  final TextEditingController _valorController = TextEditingController();
  final TextEditingController _titularController = TextEditingController();
  final TextEditingController _bancoController = TextEditingController();

  bool _solicitando = false;

  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  /// Aceita entrada tipo "1.234,56", "1234,56" ou "12.34"
  double _parseValorDigitado(String texto) {
    String t = texto.trim();
    if (t.isEmpty) return 0;
    t = t.replaceAll('R\$', '').replaceAll(' ', '');
    if (t.contains(',')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    }
    return double.tryParse(t) ?? 0.0;
  }

  /// Entradas na carteira quando corrida é cancelada pelo cliente com frete retido (estorno parcial).
  Widget _sliverCreditosCorridaCancelada(String userId) {
    return SliverToBoxAdapter(
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('pedidos')
            .where('entregador_id', isEqualTo: userId)
            .where('entregador_credito_cancelamento_feito', isEqualTo: true)
            .orderBy('entregador_credito_cancelamento_em', descending: true)
            .limit(15)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const SizedBox.shrink();
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const SizedBox.shrink();
          }
          final docs = snap.data!.docs;
          return Padding(
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(height: 36),
                Text(
                  'Créditos — corrida cancelada',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[900],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Se o cliente cancelou após você já estar indo à entrega, '
                  'o valor líquido do frete pode ser creditado aqui (reembolso parcial ao cliente).',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 14),
                ...docs.map((d) {
                  final m = d.data() as Map<String, dynamic>;
                  final valor =
                      (m['entregador_credito_cancelamento_valor'] ?? 0.0)
                          .toDouble();
                  final ts =
                      m['entregador_credito_cancelamento_em'] as Timestamp?;
                  String dataStr = '—';
                  if (ts != null) {
                    dataStr = DateFormat(
                      'dd/MM/yyyy · HH:mm',
                    ).format(ts.toDate());
                  }
                  final loja = (m['loja_nome'] ?? 'Loja').toString();
                  final idCurto = d.id.length > 8
                      ? d.id.substring(d.id.length - 8).toUpperCase()
                      : d.id.toUpperCase();
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.grey[200]!),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            backgroundColor: diPertinLaranja.withValues(
                              alpha: 0.15,
                            ),
                            child: Icon(
                              Icons.delivery_dining,
                              color: diPertinLaranja,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _moeda.format(valor),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Corrida cancelada · crédito na carteira',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Pedido $idCurto · $loja',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                Text(
                                  dataStr,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  String _mascararPix(String chave) {
    final t = chave.trim();
    if (t.isEmpty) return '—';
    if (t.length <= 4) return 'PIX ••••';
    return 'PIX •••• ${t.substring(t.length - 4)}';
  }

  /// Representa o último saque bem-sucedido do entregador, usado para
  /// pré-preencher o modal e oferecer a opção de "Usar mesmos dados".
  _UltimoSaqueDados? _ultimoSaque;

  /// Lê da coleção `saques_solicitacoes` o último pedido deste
  /// entregador para reaproveitar os dados bancários. Ignora saques
  /// recusados/estornados — só os que o entregador efetivamente usou.
  Future<_UltimoSaqueDados?> _carregarUltimoSaque(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('saques_solicitacoes')
          .where('user_id', isEqualTo: uid)
          .get();
      if (snap.docs.isEmpty) return null;

      // Ordenação em memória: os índices do Firestore podem não cobrir
      // `user_id + data_solicitacao` e aqui o volume por usuário é baixo.
      final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
        snap.docs,
      )..sort((a, b) {
          final ta = a.data()['data_solicitacao'] as Timestamp?;
          final tb = b.data()['data_solicitacao'] as Timestamp?;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta);
        });

      for (final d in docs) {
        final m = d.data();
        final status = (m['status'] ?? '').toString().toLowerCase();
        // Considera dados reutilizáveis se o saque tem chave PIX
        // preenchida e não foi marcado como recusado. Mesmo status
        // "pendente" e "pago" qualificam: o entregador informou esses
        // dados com sucesso.
        if (status == 'recusado') continue;
        final chave = (m['chave_pix'] ?? '').toString().trim();
        if (chave.isEmpty) continue;
        return _UltimoSaqueDados(
          titular: (m['titular_conta'] ?? '').toString(),
          banco: (m['banco'] ?? '').toString(),
          chavePix: chave,
        );
      }
      return null;
    } catch (e) {
      debugPrint('[carteira] _carregarUltimoSaque: $e');
      return null;
    }
  }

  Future<void> _abrirSheetSaque(double saldoDisponivel) async {
    if (saldoDisponivel <= 0) return;

    _valorController.text = _moeda
        .format(saldoDisponivel)
        .replaceAll('\u00A0', ' ');

    final uid = FirebaseAuth.instance.currentUser?.uid;
    _UltimoSaqueDados? ultimo;
    if (uid != null) {
      ultimo = _ultimoSaque ?? await _carregarUltimoSaque(uid);
      _ultimoSaque = ultimo;
    }

    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _SheetSaquePix(
          saldoDisponivel: saldoDisponivel,
          ultimoSaque: ultimo,
          moeda: _moeda,
          valorController: _valorController,
          titularController: _titularController,
          bancoController: _bancoController,
          chavePixController: _chavePixController,
          parseValor: _parseValorDigitado,
          onConfirmar: () => _confirmarSaque(saldoDisponivel, sheetContext),
        );
      },
    );
  }

  Future<void> _confirmarSaque(
    double saldoDisponivel,
    BuildContext sheetContext,
  ) async {
    final chavePix = _chavePixController.text.trim();
    final titular = _titularController.text.trim();
    final banco = _bancoController.text.trim();
    final valorSolicitado = _parseValorDigitado(_valorController.text);

    if (titular.isEmpty || banco.isEmpty || chavePix.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha todos os campos.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (valorSolicitado <= 0 || valorSolicitado > saldoDisponivel) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Valor inválido ou maior que o saldo disponível.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Confirmação biométrica antes de consumir o saldo — protege contra
    // saques acidentais e acessos rápidos por terceiros ao aparelho
    // destravado. O `sheet` fica aberto durante o prompt: em caso de
    // cancelamento ou falha, o entregador pode tentar de novo sem
    // redigitar os dados.
    final autorizado = await _autenticarSaqueComBiometria(valorSolicitado);
    if (!autorizado) return;

    if (!sheetContext.mounted) return;
    Navigator.pop(sheetContext);
    setState(() => _solicitando = true);

    try {
      await appFirebaseFunctions.httpsCallable('solicitarSaque').call({
        'tipo_usuario': 'entregador',
        'valor': valorSolicitado,
        'chave_pix': chavePix,
        'titular_conta': titular,
        'banco': banco,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Saque solicitado! A equipe analisa e faz o PIX em breve.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        _chavePixController.clear();
        _titularController.clear();
        _bancoController.clear();
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? e.code),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao solicitar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _solicitando = false);
    }
  }

  /// Garante que o saque PIX só seja disparado após confirmação biométrica
  /// (digital/face) nos aparelhos que suportam. Em dispositivos sem
  /// biometria cadastrada, seguimos adiante (comportamento legado), mas
  /// exibimos um aviso incentivando a ativação em Conta e Segurança.
  ///
  /// Retorna `true` quando o saque pode prosseguir.
  Future<bool> _autenticarSaqueComBiometria(double valor) async {
    final servico = BiometriaService.instancia;
    final disponibilidade =
        await servico.consultarDisponibilidade(forcarRefresh: true);

    if (!disponibilidade.disponivelParaUso) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.orange.shade800,
            content: const Text(
              'Seu aparelho não tem biometria ativada. Para mais segurança, '
              'cadastre uma digital/face no sistema e ative em Conta e '
              'segurança antes do próximo saque.',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return true;
    }

    final resultado = await servico.autenticarComBiometria(
      razao:
          'Confirme o saque de ${_moeda.format(valor)} com sua digital ou reconhecimento facial.',
    );

    switch (resultado) {
      case BiometriaResultado.sucesso:
        return true;
      case BiometriaResultado.cancelado:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Confirmação biométrica cancelada.'),
              backgroundColor: Colors.grey,
            ),
          );
        }
        return false;
      case BiometriaResultado.falhou:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Biometria não reconhecida. Tente novamente para liberar o saque.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      case BiometriaResultado.indisponivel:
        // Aparelho perdeu a biometria entre a leitura inicial e o prompt
        // (ex.: usuário removeu digital agora). Segue o fluxo para não
        // travar o saque; o backend ainda valida o usuário autenticado.
        return true;
      case BiometriaResultado.erro:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Não foi possível validar a biometria agora. Tente de novo.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
    }
  }

  @override
  void dispose() {
    _chavePixController.dispose();
    _valorController.dispose();
    _titularController.dispose();
    _bancoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text('Usuário não autenticado.')),
      );
    }

    final userStream = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots();
    final saquesStream = FirebaseFirestore.instance
        .collection('saques_solicitacoes')
        .where('user_id', isEqualTo: userId)
        .snapshots();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'Minha carteira',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: diPertinRoxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: StreamBuilder<DocumentSnapshot>(
              stream: userStream,
              builder: (context, userSnap) {
                return StreamBuilder<QuerySnapshot>(
                  stream: saquesStream,
                  builder: (context, saquesSnap) {
                    final userLoading =
                        userSnap.connectionState == ConnectionState.waiting;
                    final saquesLoading =
                        saquesSnap.connectionState == ConnectionState.waiting;

                    if (userLoading && !userSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    double saldoAtual = 0;
                    if (userSnap.hasData &&
                        userSnap.data!.exists &&
                        userSnap.data!.data() != null) {
                      final userData =
                          userSnap.data!.data()! as Map<String, dynamic>;
                      saldoAtual = (userData['saldo'] ?? 0.0).toDouble();
                    }

                    final docs = saquesSnap.hasData
                        ? List<QueryDocumentSnapshot>.from(
                            saquesSnap.data!.docs,
                          )
                        : <QueryDocumentSnapshot>[];

                    docs.sort((a, b) {
                      final tA =
                          (a.data() as Map<String, dynamic>)['data_solicitacao']
                              as Timestamp?;
                      final tB =
                          (b.data() as Map<String, dynamic>)['data_solicitacao']
                              as Timestamp?;
                      if (tA == null) return 1;
                      if (tB == null) return -1;
                      return tB.compareTo(tA);
                    });

                    final historicoPronto =
                        !saquesLoading && saquesSnap.hasData;

                    return CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                            child: Text(
                              'Saldo das entregas e solicitações de repasse para sua conta.',
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.35,
                                color: Colors.grey[800],
                              ),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [diPertinRoxo, Color(0xFF8E24AA)],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.12),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'Disponível para saque',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _moeda.format(saldoAtual),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 34,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: -0.5,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Atualizado em tempo real',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.85),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                if (_solicitando)
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: CircularProgressIndicator(
                                        color: diPertinLaranja,
                                      ),
                                    ),
                                  )
                                else if (saldoAtual <= 0)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: null,
                                        icon: const Icon(Icons.pix, size: 22),
                                        label: const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                          child: Text('Sacar via PIX'),
                                        ),
                                        style: FilledButton.styleFrom(
                                          disabledBackgroundColor:
                                              Colors.grey[300],
                                          disabledForegroundColor:
                                              Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Faça entregas para acumular saldo e solicitar repasse.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  FilledButton.icon(
                                    onPressed: () =>
                                        _abrirSheetSaque(saldoAtual),
                                    icon: const Icon(
                                      Icons.pix,
                                      color: Colors.white,
                                    ),
                                    label: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      child: Text(
                                        'Sacar via PIX',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: diPertinLaranja,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.amber.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        size: 22,
                                        color: Colors.amber.shade900,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Os repasses são analisados pela equipe DiPertin. '
                                          'Você acompanha o status abaixo.',
                                          style: TextStyle(
                                            fontSize: 13,
                                            height: 1.35,
                                            color: Colors.grey[900],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Histórico',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Últimas solicitações de saque',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                            ),
                          ),
                        ),
                        if (saquesLoading && !historicoPronto)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 32),
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                          )
                        else if (docs.isEmpty)
                          // Estado vazio compacto — IMPORTANTE: não usar
                          // SliverFillRemaining aqui porque ele ocupa toda a
                          // viewport restante e esconde a seção "Créditos —
                          // corrida cancelada" que vem logo abaixo
                          // (_sliverCreditosCorridaCancelada). Mantemos o
                          // visual de "empty state" em cartão compacto para
                          // que o conteúdo abaixo fique naturalmente visível.
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                32,
                                8,
                                32,
                                24,
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.receipt_long_outlined,
                                    size: 48,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Nenhum saque ainda',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Quando você solicitar um repasse, o valor e o status '
                                    'aparecem aqui.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.4,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(15, 0, 15, 32),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final saque =
                                    docs[index].data() as Map<String, dynamic>;
                                final valor = (saque['valor'] ?? 0.0)
                                    .toDouble();
                                final status = saque['status'] ?? 'pendente';
                                final chave = saque['chave_pix'] ?? '';
                                final banco = saque['banco'] ?? '';

                                String dataFormatada = '—';
                                if (saque['data_solicitacao'] != null) {
                                  final data =
                                      (saque['data_solicitacao'] as Timestamp)
                                          .toDate();
                                  dataFormatada = DateFormat(
                                    'dd/MM/yyyy · HH:mm',
                                  ).format(data);
                                }

                                Color corStatus = Colors.orange;
                                IconData iconeStatus = Icons.schedule;
                                String textoStatus = 'Pendente';

                                if (status == 'pago') {
                                  corStatus = Colors.green;
                                  iconeStatus = Icons.check_circle_outline;
                                  textoStatus = 'Pago';
                                } else if (status == 'recusado') {
                                  corStatus = Colors.red;
                                  iconeStatus = Icons.cancel_outlined;
                                  textoStatus = 'Recusado';
                                }

                                return Card(
                                  elevation: 0,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: BorderSide(color: Colors.grey[200]!),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: corStatus
                                              .withValues(alpha: 0.15),
                                          child: Icon(
                                            iconeStatus,
                                            color: corStatus,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _moeda.format(valor),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 17,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                dataFormatada,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                _mascararPix(chave),
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[800],
                                                ),
                                              ),
                                              if (banco.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  banco,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: corStatus.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Text(
                                            textoStatus,
                                            style: TextStyle(
                                              color: corStatus,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }, childCount: docs.length),
                            ),
                          ),
                        _sliverCreditosCorridaCancelada(userId),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          if (_solicitando)
            Positioned.fill(
              child: AbsorbPointer(child: Container(color: Colors.black26)),
            ),
        ],
      ),
    );
  }
}

/// Dados do último saque solicitado pelo entregador — usados para
/// pré-preencher o modal de novo saque e oferecer "usar mesma conta".
class _UltimoSaqueDados {
  const _UltimoSaqueDados({
    required this.titular,
    required this.banco,
    required this.chavePix,
  });

  final String titular;
  final String banco;
  final String chavePix;
}

/// Modal "Solicitar saque via PIX".
///
/// - Na primeira vez que o entregador solicita saque, o modal abre em
///   modo "novo cadastro": campos em branco, pedindo titular, banco e
///   chave PIX.
/// - A partir da segunda vez, o modal abre em modo "repetir último":
///   exibe um cartão com os dados do último saque e dois caminhos:
///     1. "Usar estes dados" → confirma no mesmo click.
///     2. "Usar outra conta" → alterna para o formulário em branco,
///        preservando a digitação caso o entregador mude de ideia.
class _SheetSaquePix extends StatefulWidget {
  const _SheetSaquePix({
    required this.saldoDisponivel,
    required this.ultimoSaque,
    required this.moeda,
    required this.valorController,
    required this.titularController,
    required this.bancoController,
    required this.chavePixController,
    required this.parseValor,
    required this.onConfirmar,
  });

  final double saldoDisponivel;
  final _UltimoSaqueDados? ultimoSaque;
  final NumberFormat moeda;
  final TextEditingController valorController;
  final TextEditingController titularController;
  final TextEditingController bancoController;
  final TextEditingController chavePixController;
  final double Function(String) parseValor;
  final VoidCallback onConfirmar;

  @override
  State<_SheetSaquePix> createState() => _SheetSaquePixState();
}

class _SheetSaquePixState extends State<_SheetSaquePix> {
  /// `true` → modo "resumo" (usa os dados do último saque).
  /// `false` → modo "nova conta" (formulário em branco).
  late bool _usarUltimos;

  @override
  void initState() {
    super.initState();
    final ultimo = widget.ultimoSaque;
    _usarUltimos = ultimo != null;
    if (ultimo != null) {
      widget.titularController.text = ultimo.titular;
      widget.bancoController.text = ultimo.banco;
      widget.chavePixController.text = ultimo.chavePix;
    }
  }

  String _mascararChave(String chave) {
    final t = chave.trim();
    if (t.isEmpty) return '—';
    if (t.length <= 4) return '•••• $t';
    return '•••• ${t.substring(t.length - 4)}';
  }

  void _alternarParaNovaConta() {
    setState(() {
      _usarUltimos = false;
      widget.titularController.clear();
      widget.bancoController.clear();
      widget.chavePixController.clear();
    });
  }

  void _alternarParaUltimos() {
    final ultimo = widget.ultimoSaque;
    if (ultimo == null) return;
    setState(() {
      _usarUltimos = true;
      widget.titularController.text = ultimo.titular;
      widget.bancoController.text = ultimo.banco;
      widget.chavePixController.text = ultimo.chavePix;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: diPertinLaranja.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.pix,
                        color: diPertinLaranja, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Solicitar saque via PIX',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: diPertinRoxo,
                          ),
                        ),
                        Text(
                          'Saldo disponível ${widget.moeda.format(widget.saldoDisponivel)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: widget.valorController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Valor (R\$)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(
                    Icons.attach_money,
                    color: Colors.green,
                  ),
                  suffixText:
                      'Máx. ${widget.moeda.format(widget.saldoDisponivel)}',
                  suffixStyle: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      widget.valorController.text = widget.moeda
                          .format(widget.saldoDisponivel)
                          .replaceAll('\u00A0', ' ');
                    });
                  },
                  child: const Text('Sacar tudo'),
                ),
              ),
              const SizedBox(height: 8),
              if (_usarUltimos && widget.ultimoSaque != null)
                _CardUltimaConta(
                  dados: widget.ultimoSaque!,
                  mascarar: _mascararChave,
                  onUsarOutra: _alternarParaNovaConta,
                )
              else ...[
                if (widget.ultimoSaque != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _alternarParaUltimos,
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('Usar dados do último saque'),
                      style: TextButton.styleFrom(
                        foregroundColor: diPertinRoxo,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                TextField(
                  controller: widget.titularController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome do titular',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person, color: diPertinRoxo),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: widget.bancoController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Banco (ex.: Nubank, Inter, Itaú)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(
                      Icons.account_balance,
                      color: diPertinRoxo,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: widget.chavePixController,
                  decoration: const InputDecoration(
                    labelText: 'Chave PIX',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.pix, color: diPertinLaranja),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: diPertinLaranja,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: widget.onConfirmar,
                      icon: const Icon(Icons.check_circle_outline, size: 20),
                      label: const Text(
                        'Confirmar saque',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardUltimaConta extends StatelessWidget {
  const _CardUltimaConta({
    required this.dados,
    required this.mascarar,
    required this.onUsarOutra,
  });

  final _UltimoSaqueDados dados;
  final String Function(String) mascarar;
  final VoidCallback onUsarOutra;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: diPertinRoxo.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: diPertinRoxo.withValues(alpha: 0.22),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.bookmark_added_outlined,
                    color: diPertinRoxo,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Conta do último saque',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: diPertinRoxo,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (dados.titular.trim().isNotEmpty)
                _LinhaResumo(
                  icone: Icons.person,
                  rotulo: 'Titular',
                  valor: dados.titular,
                ),
              if (dados.banco.trim().isNotEmpty)
                _LinhaResumo(
                  icone: Icons.account_balance,
                  rotulo: 'Banco',
                  valor: dados.banco,
                ),
              _LinhaResumo(
                icone: Icons.pix,
                rotulo: 'Chave PIX',
                valor: mascarar(dados.chavePix),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onUsarOutra,
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('Usar outra conta'),
            style: TextButton.styleFrom(foregroundColor: diPertinRoxo),
          ),
        ),
      ],
    );
  }
}

class _LinhaResumo extends StatelessWidget {
  const _LinhaResumo({
    required this.icone,
    required this.rotulo,
    required this.valor,
  });

  final IconData icone;
  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          SizedBox(
            width: 78,
            child: Text(
              rotulo,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(
                fontSize: 13.5,
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

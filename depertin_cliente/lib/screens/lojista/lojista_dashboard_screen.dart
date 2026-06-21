// Arquivo: lib/screens/lojista/lojista_dashboard_screen.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:depertin_cliente/constants/pedido_status.dart';
import 'package:depertin_cliente/constants/lojista_motivo_recusa.dart';
import 'package:depertin_cliente/constants/tipos_entrega.dart';
import 'package:depertin_cliente/screens/lojista/configuracoes/tipos_entrega_loja_screen.dart';
import 'package:depertin_cliente/services/conta_bloqueio_lojista_service.dart';
import 'package:depertin_cliente/utils/lojista_acesso_app.dart';
import 'package:depertin_cliente/utils/lojista_contagem_novos.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:depertin_cliente/screens/cliente/chat_suporte_screen.dart';
import 'package:depertin_cliente/screens/comum/configuracao_notificacoes_screen.dart';
import 'package:depertin_cliente/screens/lojista/lojista_avaliacoes_screen.dart';
import 'lojista_pedidos_screen.dart';
import 'lojista_produtos_screen.dart';
import 'lojista_cupons_screen.dart';
import 'lojista_config_screen.dart';
import 'lojista_encomendas_screen.dart';

const Color diPertinLaranja = Color(0xFFFF8F00);
const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinRoxoEscuro = Color(0xFF4A0B7C);
const Color _fundoTela = Color(0xFFF7F5FA);
const Color _tintaForte = Color(0xFF17162A);
const Color _tintaMedia = Color(0xFF5A5870);
const Color _bordaSuave = Color(0xFFECE8F2);

enum _PassoPendenteEstado { concluido, ativo, aguardando }

class LojistaDashboardScreen extends StatefulWidget {
  const LojistaDashboardScreen({super.key});

  @override
  State<LojistaDashboardScreen> createState() => _LojistaDashboardScreenState();
}

class _LojistaDashboardScreenState extends State<LojistaDashboardScreen> {
  final String _authUid = FirebaseAuth.instance.currentUser!.uid;
  String _uidLoja = FirebaseAuth.instance.currentUser!.uid;
  int _nivel = 3;
  bool _gpsAtualizado = false;
  bool _migracaoRealizada = false;

  StreamSubscription<DocumentSnapshot>? _userDocSub;
  Map<String, dynamic>? _dadosUsuario;
  bool _carregandoUsuario = true;
  bool _docExiste = true;
  bool _entradaAnimada = false;

  Future<void> _migrarDadosLojista(Map<String, dynamic> dados) async {
    if (_migracaoRealizada) return;

    final lojaNome = dados['loja_nome'];
    if (lojaNome != null && lojaNome.toString().trim().isNotEmpty) {
      _migracaoRealizada = true;
      return;
    }

    final String nomeAtual = dados['nome']?.toString() ?? 'Minha Loja';
    try {
      await FirebaseFirestore.instance.collection('users').doc(_authUid).update(
        {'loja_nome': nomeAtual},
      );
      _migracaoRealizada = true;
      if (kDebugMode) {
        debugPrint('Zelador: nome migrado para loja_nome.');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Erro na migração loja_nome: $e');
      }
    }
  }

  Future<void> _atualizarLocalizacaoNoBanco() async {
    if (_gpsAtualizado) return;

    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    final Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    await FirebaseFirestore.instance.collection('users').doc(_authUid).update({
      'latitude': position.latitude,
      'longitude': position.longitude,
    });

    _gpsAtualizado = true;
    if (kDebugMode) {
      debugPrint('GPS atualizado: ${position.latitude}, ${position.longitude}');
    }
  }

  void _aplicarTarefasPosAprovacao(Map<String, dynamic> dados) {
    _migrarDadosLojista(dados);
    _atualizarLocalizacaoNoBanco();
  }

  void _onUserDocument(DocumentSnapshot snap) {
    unawaited(_processarSnapshotUsuario(snap));
  }

  Future<void> _processarSnapshotUsuario(DocumentSnapshot snap) async {
    if (!mounted) return;

    if (!snap.exists) {
      setState(() {
        _dadosUsuario = null;
        _docExiste = false;
        _carregandoUsuario = false;
      });
      return;
    }

    await ContaBloqueioLojistaService.sincronizarLiberacaoSeExpirado(_authUid);
    if (!mounted) return;

    final fresh = await FirebaseFirestore.instance
        .collection('users')
        .doc(_authUid)
        .get();
    if (!fresh.exists || !mounted) return;

    var dados = fresh.data() as Map<String, dynamic>;
    final ownerUid = dados['lojista_owner_uid']?.toString().trim() ?? '';

    // Colaborador: busca dados da loja do dono para herdar status/nome.
    if (ownerUid.isNotEmpty && ownerUid != _authUid) {
      final ownerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(ownerUid)
          .get();
      if (ownerDoc.exists && mounted) {
        final ownerData = ownerDoc.data() as Map<String, dynamic>;
        dados = {
          ...dados,
          'status_loja': ownerData['status_loja'] ?? dados['status_loja'],
          'loja_nome': ownerData['loja_nome'] ?? ownerData['nome'],
          'loja_aberta': ownerData['loja_aberta'] ?? dados['loja_aberta'],
          'nome_loja': ownerData['nome_loja'] ?? ownerData['loja_nome'],
        };
      }
    }

    if (!mounted) return;

    final status = dados['status_loja'] ?? 'pendente';

    setState(() {
      _dadosUsuario = dados;
      _docExiste = true;
      _carregandoUsuario = false;
      _uidLoja = uidLojaEfetivo(dados);
      _nivel = nivelAcessoLojista(dados);
    });

    if (status == 'aprovado' || status == 'aprovada' || status == 'ativo') {
      _aplicarTarefasPosAprovacao(dados);
    }
  }

  @override
  void initState() {
    super.initState();
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(_authUid)
        .snapshots()
        .listen(_onUserDocument);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entradaAnimada = true);
    });
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
    super.dispose();
  }

  static final Set<String> _statusAndamento = PedidoStatus.andamentoLojista;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundoTela,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Painel do Lojista',
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
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sair da conta',
            onPressed: _confirmarLogout,
          ),
        ],
      ),
      body: _corpoPainel(),
    );
  }

  Future<void> _confirmarLogout() async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: diPertinRoxo.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout_rounded, color: diPertinRoxo),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Sair da conta?',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _tintaForte,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Você precisará entrar novamente para acessar o painel.',
          style: TextStyle(height: 1.5, color: _tintaMedia),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: diPertinRoxo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sair',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.pop(context);
  }

  String _saudacaoPorHorario() {
    final hora = DateTime.now().hour;
    if (hora < 12) return 'Bom dia';
    if (hora < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  String _dataExtensa() {
    try {
      return DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(DateTime.now());
    } catch (_) {
      return DateFormat("EEEE, d 'de' MMMM").format(DateTime.now());
    }
  }

  Widget _corpoPainel() {
    if (_carregandoUsuario) {
      return const Center(
        child: CircularProgressIndicator(color: diPertinLaranja),
      );
    }

    if (!_docExiste || _dadosUsuario == null) {
      return const Center(child: Text('Erro ao carregar dados.'));
    }

    final dados = _dadosUsuario!;
    final String status = dados['status_loja'] ?? 'pendente';

    final bloqueioAte = LojistaMotivoRecusa.bloqueioCadastroAte(dados);
    if (bloqueioAte != null) {
      return _construirRecusaComBloqueio(dados, bloqueioAte);
    }

    if (ContaBloqueioLojistaService.lojaRecusadaSomenteCorrecaoCadastro(
      dados,
    )) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.edit_note_rounded,
                size: 80,
                color: Colors.red.shade700,
              ),
              const SizedBox(height: 20),
              const Text(
                'Cadastro precisa de ajustes',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                'Abra o perfil e use «Corrigir cadastro da loja» para enviar os documentos novamente.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (status == 'pendente') {
      return _construirAprovacaoPendente(dados);
    }

    final String nomeParaExibir =
        dados['loja_nome'] ?? dados['nome'] ?? 'Lojista';
    final bool lojaAberta = dados['loja_aberta'] != false;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _heroHeader(nomeParaExibir, lojaAberta)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          sliver: SliverToBoxAdapter(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('pedidos')
                  .where('loja_id', isEqualTo: _uidLoja)
                  .snapshots(),
              builder: (context, snapshotPedidos) {
                final carregandoPedidos =
                    snapshotPedidos.connectionState ==
                        ConnectionState.waiting &&
                    !snapshotPedidos.hasData;

                final pedidosDocs = snapshotPedidos.data?.docs ?? [];
                int novosPedidos = 0;
                int andamento = 0;
                if (!carregandoPedidos) {
                  novosPedidos = LojistaContagemNovos.contarPedidosNovos(
                    pedidosDocs,
                  );
                  for (final doc in pedidosDocs) {
                    final s = ((doc.data() as Map)['status'] ?? 'pendente')
                        .toString();
                    if (_statusAndamento.contains(s)) andamento++;
                  }
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('encomendas')
                      .where('loja_id', isEqualTo: _uidLoja)
                      .snapshots(),
                  builder: (context, snapshotEncomendas) {
                    final carregandoEncomendas =
                        snapshotEncomendas.connectionState ==
                            ConnectionState.waiting &&
                        !snapshotEncomendas.hasData;
                    final carregando = carregandoPedidos || carregandoEncomendas;

                    final encomendaDocs = snapshotEncomendas.data?.docs ?? [];
                    final novosEncomendas =
                        LojistaContagemNovos.contarEncomendasNovas(
                          encomendaDocs,
                        );
                    final novosTotal = novosPedidos + novosEncomendas;

                    final _AlertaIncompat? alertaIncompat =
                        _AlertaIncompat.deDados(dados);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (TiposEntrega.lerDeDoc(dados).isEmpty)
                          _alertaTiposEntregaPendente()
                        else if (alertaIncompat != null && alertaIncompat.ativo)
                          _alertaTiposEntregaIncompat(alertaIncompat),
                        _linhaKpis(
                          novos: carregando ? null : novosTotal,
                          andamento: carregandoPedidos ? null : andamento,
                        ),
                        const SizedBox(height: 28),
                        _tituloSecao('GESTÃO', 'O que você deseja gerenciar?'),
                        const SizedBox(height: 16),
                        Column(
                          children: _menusLojistaPorNivel(
                            dados,
                            badgeNovos: !carregandoPedidos && novosPedidos > 0
                                ? novosPedidos
                                : null,
                            badgeEncomendas: novosEncomendas > 0
                                ? novosEncomendas
                                : null,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _bannerPainelWeb(),
                        const SizedBox(height: 12),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _heroHeader(String nome, bool aberta) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_diPertinRoxoEscuro, diPertinRoxo, Color(0xFF8E24AA)],
        ),
      ),
      child: Stack(
        children: [
          // Decor radial sutil atrás do conteúdo
          Positioned(
            top: -30,
            right: -40,
            child: _decorRadial(160, Colors.white.withValues(alpha: 0.08)),
          ),
          Positioned(
            bottom: -50,
            left: -60,
            child: _decorRadial(180, diPertinLaranja.withValues(alpha: 0.18)),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.of(context).padding.top + kToolbarHeight + 8,
              20,
              26,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dataExtensa().toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${_saudacaoPorHorario()},',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  nome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.18,
                  ),
                ),
                const SizedBox(height: 14),
                _chipStatusLoja(aberta),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _decorRadial(double size, Color cor) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [cor, cor.withValues(alpha: 0)]),
        ),
      ),
    );
  }

  Widget _alertaTiposEntregaPendente() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade300, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red.shade800,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Configure os tipos de entrega',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.red.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Sua loja ainda não informou quais veículos aceita para entregas '
            '(bicicleta, moto, carro ou carro frete). Sem essa configuração '
            'o sistema usa um padrão genérico que pode não atender seus '
            'produtos — o que leva a recusas de entregadores e atrasos.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Colors.red.shade900,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TiposEntregaLojaScreen(),
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text(
                'Configurar agora',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Alerta âmbar exibido quando um entregador cancelou uma corrida desta
  /// loja reportando "veículo incompatível". Sinal que a config de
  /// `tipos_entrega_permitidos` pode estar inconsistente com o que a loja
  /// realmente entrega. Não bloqueia nada — só chama atenção. O lojista
  /// pode dispensar após revisar.
  Widget _alertaTiposEntregaIncompat(_AlertaIncompat a) {
    final ultimo = a.ultimoEm;
    final ultimoTxt = ultimo == null
        ? ''
        : ' (último em ${DateFormat('dd/MM HH:mm').format(ultimo)})';
    final tiposAceitos = a.ultimoTiposAceitosLoja
        .map(TiposEntrega.rotulo)
        .join(', ');
    final tipoEntreg = a.ultimoTipoEntregador.isEmpty
        ? 'não informado'
        : TiposEntrega.rotulo(a.ultimoTipoEntregador);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.shade400, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.pedal_bike_rounded,
                  color: Colors.amber.shade900,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Revise os tipos de entrega',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Entregadores já reportaram ${a.totalUltimos30d} cancelamento(s) '
            'desta loja marcando "produto incompatível com meu veículo"$ultimoTxt. '
            'Isso não penaliza o entregador e o pedido foi redespachado '
            'automaticamente — mas indica que a configuração atual pode não '
            'refletir a carga real dos seus produtos.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Colors.amber.shade900,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Último evento',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: Colors.amber.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 12, height: 1.35),
                    children: [
                      const TextSpan(text: 'Veículo do entregador: '),
                      TextSpan(
                        text: tipoEntreg,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                if (tiposAceitos.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text.rich(
                      TextSpan(
                        style: const TextStyle(fontSize: 12, height: 1.35),
                        children: [
                          const TextSpan(text: 'Sua loja aceita: '),
                          TextSpan(
                            text: tiposAceitos,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _dispensarAlertaIncompat,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.amber.shade900,
                    side: BorderSide(color: Colors.amber.shade400),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text(
                    'Já revisei',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TiposEntregaLojaScreen(),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.amber.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: const Text(
                    'Revisar',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Grava `dispensado_em = now` dentro de `alerta_tipos_entrega_incompat`.
  /// A UI passa a esconder o alerta quando `dispensado_em >= ultimo_em`.
  /// Não zera o contador — preserva o histórico.
  Future<void> _dispensarAlertaIncompat() async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(_uidLoja).set({
        'alerta_tipos_entrega_incompat': {
          'dispensado_em': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alerta dispensado. Reaparece se houver novo caso.'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao dispensar: $e')));
    }
  }

  Widget _tituloSecao(String label, String titulo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 2,
              decoration: BoxDecoration(
                color: diPertinLaranja,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
                color: diPertinLaranja.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: _tintaForte,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  Widget _linhaKpis({int? novos, int? andamento}) {
    return Row(
      children: [
        Expanded(
          child: _cardKpi(
            valor: novos,
            legenda: 'Novos',
            icone: Icons.notifications_active_rounded,
            cor: diPertinRoxo,
            gradiente: const [Color(0xFFF5EEFC), Color(0xFFFAF5FE)],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _cardKpi(
            valor: andamento,
            legenda: 'Em andamento',
            icone: Icons.local_shipping_rounded,
            cor: diPertinLaranja,
            gradiente: const [Color(0xFFFFF3E0), Color(0xFFFFF9F0)],
          ),
        ),
      ],
    );
  }

  Widget _cardKpi({
    required int? valor,
    required String legenda,
    required IconData icone,
    required Color cor,
    required List<Color> gradiente,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradiente,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _bordaSuave, width: 1),
        boxShadow: [
          BoxShadow(
            color: cor.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icone, color: cor, size: 18),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 14),
          if (valor == null)
            SizedBox(
              height: 30,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: cor,
                  ),
                ),
              ),
            )
          else
            Text(
              '$valor',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: cor,
                height: 1,
                letterSpacing: -1,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            legenda,
            style: const TextStyle(
              fontSize: 12.5,
              color: _tintaMedia,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerPainelWeb() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _bordaSuave),
        boxShadow: [
          BoxShadow(
            color: diPertinRoxo.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  diPertinRoxo.withValues(alpha: 0.10),
                  diPertinLaranja.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.insights_rounded,
              color: diPertinRoxo,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Relatórios financeiros',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _tintaForte,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Acesse o painel web para relatórios completos.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: _tintaMedia,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _menusLojistaPorNivel(
    Map<String, dynamic> dados, {
    int? badgeNovos,
    int? badgeEncomendas,
  }) {
    final itens = <Widget>[];

    // Nível 1+: Pedidos (todos veem)
    itens.add(
      _buildMenuCard(
        context,
        titulo: 'Gestão de pedidos',
        subtitulo: 'Aceite, recuse e acompanhe entregas',
        icone: Icons.receipt_long_rounded,
        cor: const Color(0xFF2E6BE6),
        telaDestino: LojistaPedidosScreen(uidLoja: _uidLoja),
        badgeCount: badgeNovos,
      ),
    );

    itens.add(const SizedBox(height: 12));
    itens.add(
      _buildMenuCard(
        context,
        titulo: 'Encomendas',
        subtitulo: 'Propostas e mensagens de clientes',
        icone: Icons.handshake_outlined,
        cor: const Color(0xFF5E35B1),
        telaDestino: LojistaEncomendasScreen(uidLoja: _uidLoja),
        badgeCount: badgeEncomendas,
      ),
    );

    // Nível 2+: Produtos + cupons
    if (_nivel >= 2) {
      itens.add(const SizedBox(height: 12));
      itens.add(
        _buildMenuCard(
          context,
          titulo: 'Meu estoque',
          subtitulo: 'Cadastre e edite seus produtos',
          icone: Icons.inventory_2_rounded,
          cor: const Color(0xFF0F9D8A),
          telaDestino: LojistaProdutosScreen(uidLoja: _uidLoja),
        ),
      );
      itens.add(const SizedBox(height: 12));
      itens.add(
        _buildMenuCard(
          context,
          titulo: 'Cupons & promoções',
          subtitulo: 'Descontos e frete grátis para seus clientes',
          icone: Icons.local_offer_rounded,
          cor: const Color(0xFFC2185B),
          telaDestino: LojistaCuponsScreen(uidLoja: _uidLoja),
        ),
      );
    }

    // Nível 3: Config + Avaliações
    if (_nivel >= 3) {
      itens.add(const SizedBox(height: 12));
      itens.add(
        _buildMenuCard(
          context,
          titulo: 'Configurações da loja',
          subtitulo: 'Horários, nome e status de funcionamento',
          icone: Icons.storefront_rounded,
          cor: diPertinRoxo,
          telaDestino: LojistaConfigScreen(dadosAtuaisDaLoja: dados),
        ),
      );
      itens.add(const SizedBox(height: 12));
      itens.add(
        _buildMenuCard(
          context,
          titulo: 'Avaliações de clientes',
          subtitulo: 'Feedbacks e notas da sua loja',
          icone: Icons.star_rounded,
          cor: const Color(0xFFE5A21B),
          telaDestino: LojistaAvaliacoesScreen(uidLoja: _uidLoja),
        ),
      );
    }

    return itens;
  }

  String? _formatarDataSolicitacaoLoja(Map<String, dynamic> dados) {
    final raw = dados['data_solicitacao_loja'];
    if (raw is! Timestamp) return null;
    final dt = raw.toDate();
    try {
      return DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR').format(dt);
    } catch (_) {
      return DateFormat("dd/MM/yyyy 'às' HH:mm").format(dt);
    }
  }

  String _mascararDocumentoLoja(dynamic bruto) {
    final digitos = bruto.toString().replaceAll(RegExp(r'\D'), '');
    if (digitos.isEmpty) return '—';
    if (digitos.length == 11) {
      return '***.${digitos.substring(3, 6)}.${digitos.substring(6, 9)}-**';
    }
    if (digitos.length == 14) {
      return '**.${digitos.substring(2, 5)}.${digitos.substring(5, 8)}/****-**';
    }
    return 'Documento enviado';
  }

  Widget _cardPendenteSuperficie({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _bordaSuave),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1530).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }

  Widget _chipEmAnalise() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DotPulsante(cor: diPertinLaranja),
          const SizedBox(width: 8),
          const Text(
            'Em análise',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroAprovacaoPendente(String nomeLoja, bool ehColaborador) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_diPertinRoxoEscuro, diPertinRoxo, Color(0xFF8E24AA)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -30,
            right: -40,
            child: _decorRadial(160, Colors.white.withValues(alpha: 0.08)),
          ),
          Positioned(
            bottom: -50,
            left: -60,
            child: _decorRadial(180, diPertinLaranja.withValues(alpha: 0.18)),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.of(context).padding.top + kToolbarHeight + 8,
              20,
              26,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dataExtensa().toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${_saudacaoPorHorario()},',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  nomeLoja,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.18,
                  ),
                ),
                const SizedBox(height: 14),
                _chipEmAnalise(),
                if (ehColaborador) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Você é colaborador desta loja. O painel completo libera '
                    'quando o responsável for aprovado.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _passoPendente({
    required String rotulo,
    required IconData icone,
    required _PassoPendenteEstado estado,
  }) {
    final Color cor = switch (estado) {
      _PassoPendenteEstado.concluido => const Color(0xFF2E7D32),
      _PassoPendenteEstado.ativo => diPertinLaranja,
      _PassoPendenteEstado.aguardando => Colors.grey.shade400,
    };
    final Color fundo = switch (estado) {
      _PassoPendenteEstado.concluido => const Color(0xFFE8F5E9),
      _PassoPendenteEstado.ativo => diPertinLaranja.withValues(alpha: 0.12),
      _PassoPendenteEstado.aguardando => Colors.grey.shade100,
    };

    return Expanded(
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: fundo,
              shape: BoxShape.circle,
              border: Border.all(
                color: cor.withValues(alpha: estado == _PassoPendenteEstado.aguardando ? 0.5 : 1),
                width: estado == _PassoPendenteEstado.ativo ? 2 : 1,
              ),
            ),
            child: Icon(
              estado == _PassoPendenteEstado.concluido
                  ? Icons.check_rounded
                  : icone,
              color: cor,
              size: 20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            rotulo,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: estado == _PassoPendenteEstado.aguardando
                  ? _tintaMedia
                  : _tintaForte,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _linhaPassosPendente() {
    return Row(
      children: [
        _passoPendente(
          rotulo: 'Envio',
          icone: Icons.upload_file_rounded,
          estado: _PassoPendenteEstado.concluido,
        ),
        Expanded(
          child: Container(
            height: 2,
            margin: const EdgeInsets.only(bottom: 28),
            color: diPertinLaranja.withValues(alpha: 0.35),
          ),
        ),
        _passoPendente(
          rotulo: 'Análise',
          icone: Icons.fact_check_outlined,
          estado: _PassoPendenteEstado.ativo,
        ),
        Expanded(
          child: Container(
            height: 2,
            margin: const EdgeInsets.only(bottom: 28),
            color: Colors.grey.shade300,
          ),
        ),
        _passoPendente(
          rotulo: 'Loja ativa',
          icone: Icons.storefront_rounded,
          estado: _PassoPendenteEstado.aguardando,
        ),
      ],
    );
  }

  Widget _itemDicaPendente({required IconData icone, required String texto}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 20, color: diPertinRoxo),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.grey.shade800,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linhaResumoPendente(String rotulo, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              rotulo,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: _tintaForte,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Painel exibido enquanto `status_loja == pendente` (cadastro em análise).
  Widget _construirAprovacaoPendente(Map<String, dynamic> dados) {
    final nomeLoja =
        (dados['loja_nome'] ?? dados['nome'] ?? 'Sua loja').toString().trim();
    final ownerUid = dados['lojista_owner_uid']?.toString().trim() ?? '';
    final ehColaborador = ownerUid.isNotEmpty && ownerUid != _authUid;
    final dataEnvio = _formatarDataSolicitacaoLoja(dados);
    final tipoDoc = (dados['loja_tipo_documento'] ?? 'CPF').toString();
    final docMascarado = _mascararDocumentoLoja(dados['loja_documento']);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _heroAprovacaoPendente(nomeLoja, ehColaborador),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          sliver: SliverToBoxAdapter(
            child: AnimatedOpacity(
              opacity: _entradaAnimada ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _cardPendenteSuperficie(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    diPertinLaranja.withValues(alpha: 0.18),
                                    diPertinRoxo.withValues(alpha: 0.12),
                                  ],
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.hourglass_top_rounded,
                                color: diPertinLaranja,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Cadastro em análise',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: _tintaForte,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    dataEnvio != null
                                        ? 'Recebemos sua solicitação em $dataEnvio.'
                                        : 'Recebemos sua solicitação. Nossa equipe '
                                            'está analisando nome, documentos e endereço.',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: Colors.grey.shade700,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: diPertinRoxo.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: diPertinRoxo.withValues(alpha: 0.14),
                            ),
                          ),
                          child: Text(
                            'Em geral respondemos em até 05 dias úteis. '
                            'Você receberá uma notificação no celular assim que '
                            'houver resultado — não é preciso reenviar o cadastro.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade800,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _cardPendenteSuperficie(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'O que acontece agora',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _tintaForte,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _linhaPassosPendente(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _cardPendenteSuperficie(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Resumo do envio',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _tintaForte,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _linhaResumoPendente('Loja', nomeLoja),
                        _linhaResumoPendente(
                          'Tipo',
                          tipoDoc == 'CNPJ' ? 'Empresa (CNPJ)' : 'Autônomo (CPF)',
                        ),
                        _linhaResumoPendente(
                          tipoDoc == 'CNPJ' ? 'CNPJ' : 'CPF',
                          docMascarado,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Os documentos anexados não podem ser alterados '
                          'enquanto a análise estiver em andamento.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            height: 1.4,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _cardPendenteSuperficie(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Enquanto isso',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _tintaForte,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _itemDicaPendente(
                          icone: Icons.notifications_active_outlined,
                          texto:
                              'Mantenha as notificações ativas para saber na hora '
                              'quando sua loja for aprovada ou se precisar de ajustes.',
                        ),
                        _itemDicaPendente(
                          icone: Icons.sync_rounded,
                          texto:
                              'Esta tela atualiza sozinha quando o status mudar. '
                              'Você também pode sair e voltar depois.',
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 46,
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    const ConfiguracaoNotificacoesScreen(),
                              ),
                            ),
                            icon: const Icon(Icons.tune_rounded, size: 20),
                            label: const Text(
                              'Configurar notificações',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: diPertinRoxo,
                              side: BorderSide(
                                color: diPertinRoxo.withValues(alpha: 0.35),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const ChatSuporteScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.support_agent_rounded, size: 22),
                      label: const Text(
                        'Falar com o suporte',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: diPertinRoxo,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Tela exibida quando o lojista foi recusado por motivo de bloqueio
  /// (`DESINTERESSE_COMERCIAL` ou `OUTROS`) e ainda não cumpriu os 30 dias.
  Widget _construirRecusaComBloqueio(
    Map<String, dynamic> dados,
    DateTime bloqueioAte,
  ) {
    final formato = DateFormat("dd 'de' MMMM 'de' y", 'pt_BR');
    final dataFormatada = formato.format(bloqueioAte);
    final codigo = LojistaMotivoRecusa.codigoDoDocumento(dados);
    final rotulo = codigo != null ? LojistaMotivoRecusa.rotulo(codigo) : null;
    final mensagem = (dados['motivo_recusa'] ?? '').toString().trim();
    final descricao = (dados['motivo_recusa_descricao'] ?? '')
        .toString()
        .trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: diPertinRoxo.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_clock_rounded,
                size: 64,
                color: diPertinRoxo,
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Cadastro não aprovado',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: diPertinRoxo,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Após a análise das informações enviadas, seu cadastro não foi '
            'aprovado neste momento.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              color: Colors.grey.shade800,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              border: Border.all(color: Colors.red.shade200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.red.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Motivo da recusa',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.red.shade700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                if (rotulo != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Classificação: $rotulo',
                    style: TextStyle(
                      color: Colors.red.shade900,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ],
                if (descricao.isNotEmpty &&
                    codigo == LojistaMotivoRecusa.outros) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Detalhe: $descricao',
                    style: TextStyle(
                      color: Colors.red.shade900,
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                ],
                if (mensagem.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    mensagem,
                    style: TextStyle(
                      color: Colors.red.shade900,
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: diPertinRoxo.withValues(alpha: 0.06),
              border: Border.all(color: diPertinRoxo.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.event_available_outlined,
                  color: diPertinRoxo,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Colors.grey.shade800,
                        height: 1.5,
                      ),
                      children: [
                        const TextSpan(
                          text:
                              'Você poderá solicitar uma nova análise a partir de ',
                        ),
                        TextSpan(
                          text: dataFormatada,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: diPertinRoxo,
                          ),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Em caso de dúvida, entre em contato com o suporte.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _chipStatusLoja(bool aberta) {
    final Color corBase = aberta
        ? const Color(0xFF1BB76E)
        : const Color(0xFFE05454);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DotPulsante(cor: aberta ? const Color(0xFF2BE28F) : corBase),
          const SizedBox(width: 8),
          Text(
            aberta ? 'Loja aberta' : 'Loja fechada',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required String titulo,
    required String subtitulo,
    required IconData icone,
    required Color cor,
    required Widget telaDestino,
    int? badgeCount,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => telaDestino),
          );
        },
        splashColor: cor.withValues(alpha: 0.08),
        highlightColor: cor.withValues(alpha: 0.04),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _bordaSuave),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A1530).withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            cor.withValues(alpha: 0.18),
                            cor.withValues(alpha: 0.08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      alignment: Alignment.center,
                      child: Icon(icone, color: cor, size: 22),
                    ),
                    if (badgeCount != null && badgeCount > 0)
                      Positioned(
                        right: -5,
                        top: -5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE53935),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFE53935,
                                ).withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          constraints: const BoxConstraints(minWidth: 20),
                          child: Text(
                            badgeCount > 99 ? '99+' : '$badgeCount',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: _tintaForte,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitulo,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: _tintaMedia,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _fundoTela,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: _tintaMedia,
                    size: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bolinha com pulso animado (indicador de status "ao vivo").
class _DotPulsante extends StatefulWidget {
  final Color cor;
  const _DotPulsante({required this.cor});

  @override
  State<_DotPulsante> createState() => _DotPulsanteState();
}

class _DotPulsanteState extends State<_DotPulsante>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 10,
      height: 10,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t = _ctrl.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 10 + (t * 8),
                height: 10 + (t * 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.cor.withValues(alpha: (1 - t) * 0.35),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.cor,
                  boxShadow: [
                    BoxShadow(
                      color: widget.cor.withValues(alpha: 0.7),
                      blurRadius: 5,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Snapshot imutável do campo `alerta_tipos_entrega_incompat` persistido no
/// doc do lojista. Criado pelo callable
/// `entregadorCancelarPorIncompatibilidade` e dispensado pelo próprio
/// lojista gravando `dispensado_em`.
class _AlertaIncompat {
  _AlertaIncompat({
    required this.totalUltimos30d,
    required this.ultimoEm,
    required this.dispensadoEm,
    required this.ultimoPedidoId,
    required this.ultimoTipoEntregador,
    required this.ultimoTiposAceitosLoja,
  });

  final int totalUltimos30d;
  final DateTime? ultimoEm;
  final DateTime? dispensadoEm;
  final String ultimoPedidoId;
  final String ultimoTipoEntregador;
  final List<String> ultimoTiposAceitosLoja;

  /// Ativo se houve pelo menos um evento e ainda não foi dispensado, ou se
  /// o último evento é mais recente que o último dispensado_em.
  bool get ativo {
    if (totalUltimos30d <= 0) return false;
    if (ultimoEm == null) return false;
    if (dispensadoEm == null) return true;
    return ultimoEm!.isAfter(dispensadoEm!);
  }

  static _AlertaIncompat? deDados(Map<String, dynamic>? d) {
    if (d == null) return null;
    final raw = d['alerta_tipos_entrega_incompat'];
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    DateTime? ts(dynamic v) =>
        v is Timestamp ? v.toDate() : (v is DateTime ? v : null);
    final aceitos = (m['ultimo_tipos_aceitos_loja'] is Iterable)
        ? List<String>.from(
            (m['ultimo_tipos_aceitos_loja'] as Iterable)
                .map((e) => e?.toString() ?? '')
                .where((s) => s.isNotEmpty),
          )
        : <String>[];
    return _AlertaIncompat(
      totalUltimos30d: (m['total_ultimos_30d'] is num)
          ? (m['total_ultimos_30d'] as num).toInt()
          : 0,
      ultimoEm: ts(m['ultimo_em']),
      dispensadoEm: ts(m['dispensado_em']),
      ultimoPedidoId: m['ultimo_pedido_id']?.toString() ?? '',
      ultimoTipoEntregador: m['ultimo_tipo_entregador']?.toString() ?? '',
      ultimoTiposAceitosLoja: aceitos,
    );
  }
}

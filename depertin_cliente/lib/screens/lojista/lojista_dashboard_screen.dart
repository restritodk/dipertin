// Arquivo: lib/screens/lojista/lojista_dashboard_screen.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:depertin_cliente/constants/pedido_status.dart';
import 'package:depertin_cliente/constants/lojista_motivo_recusa.dart';
import 'package:depertin_cliente/services/conta_bloqueio_lojista_service.dart';
import 'package:depertin_cliente/utils/lojista_acesso_app.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:depertin_cliente/screens/lojista/lojista_avaliacoes_screen.dart';
import 'lojista_pedidos_screen.dart';
import 'lojista_produtos_screen.dart';
import 'lojista_config_screen.dart';

const Color diPertinLaranja = Color(0xFFFF8F00);
const Color diPertinRoxo = Color(0xFF6A1B9A);

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

  Future<void> _migrarDadosLojista(Map<String, dynamic> dados) async {
    if (_migracaoRealizada) return;

    final lojaNome = dados['loja_nome'];
    if (lojaNome != null && lojaNome.toString().trim().isNotEmpty) {
      _migracaoRealizada = true;
      return;
    }

    final String nomeAtual = dados['nome']?.toString() ?? 'Minha Loja';
    try {
      await FirebaseFirestore.instance.collection('users').doc(_authUid).update({
        'loja_nome': nomeAtual,
      });
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
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
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
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'Painel do Lojista',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: diPertinLaranja,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: 'Sair da conta',
            onPressed: () async {
              final bool? confirmar = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: const Row(
                    children: [
                      Icon(Icons.logout, color: diPertinLaranja),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sair da conta?',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  content: const Text(
                    'Você precisará entrar de novo para acessar o painel do lojista.',
                    style: TextStyle(height: 1.4),
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
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Sair'),
                    ),
                  ],
                ),
              );
              if (confirmar != true || !context.mounted) return;
              await FirebaseAuth.instance.signOut();
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: _corpoPainel(),
    );
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

    if (ContaBloqueioLojistaService.lojaRecusadaSomenteCorrecaoCadastro(dados)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.edit_note_rounded, size: 80, color: Colors.red.shade700),
              const SizedBox(height: 20),
              const Text(
                'Cadastro precisa de ajustes',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Abra o perfil e use «Corrigir cadastro da loja» para enviar os documentos novamente.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 16, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    if (status == 'pendente') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hourglass_empty, size: 80, color: diPertinLaranja),
              const SizedBox(height: 20),
              const Text(
                'Aprovação pendente',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Sua loja está em análise. Aguarde o administrador aprovar o seu cadastro para começar a vender.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    final String nomeParaExibir =
        dados['loja_nome'] ?? dados['nome'] ?? 'Lojista';
    final bool lojaAberta = dados['loja_aberta'] != false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Olá, $nomeParaExibir!',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Resumo de hoje',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              _chipStatusLoja(lojaAberta),
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('pedidos')
                .where('loja_id', isEqualTo: _uidLoja)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: diPertinLaranja,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'O que você deseja gerenciar?',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    ..._menusLojistaPorNivel(dados, badgeNovos: null),
                  ],
                );
              }

              final docs = snapshot.data?.docs ?? [];
              int novos = 0;
              int andamento = 0;
              for (final doc in docs) {
                final m = doc.data() as Map<String, dynamic>;
                final s = m['status'] ?? 'pendente';
                if (s == 'pendente') {
                  novos++;
                } else if (_statusAndamento.contains(s)) {
                  andamento++;
                }
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _celulaResumo(
                              valor: '$novos',
                              legenda: 'Novos',
                              icone: Icons.notifications_active_outlined,
                              cor: Colors.blue.shade700,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 44,
                            color: Colors.grey.shade300,
                          ),
                          Expanded(
                            child: _celulaResumo(
                              valor: '$andamento',
                              legenda: 'Em andamento',
                              icone: Icons.soup_kitchen_outlined,
                              cor: diPertinLaranja,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'O que você deseja gerenciar?',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  ..._menusLojistaPorNivel(
                    dados,
                    badgeNovos: novos > 0 ? novos : null,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: diPertinLaranja.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: diPertinLaranja.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.desktop_windows, color: diPertinLaranja, size: 30),
                SizedBox(width: 15),
                Expanded(
                  child: Text(
                    'Lembrete: acesse o painel web para relatórios financeiros completos.',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
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
  }) {
    final itens = <Widget>[];

    // Nível 1+: Pedidos (todos veem)
    itens.add(_buildMenuCard(
      context,
      titulo: 'Gestão de pedidos',
      subtitulo: 'Aceite, recuse e acompanhe entregas',
      icone: Icons.receipt_long,
      cor: Colors.blue,
      telaDestino: LojistaPedidosScreen(uidLoja: _uidLoja),
      badgeCount: badgeNovos,
    ));

    // Nível 2+: Produtos
    if (_nivel >= 2) {
      itens.add(const SizedBox(height: 15));
      itens.add(_buildMenuCard(
        context,
        titulo: 'Meu estoque',
        subtitulo: 'Cadastre e edite seus produtos',
        icone: Icons.inventory_2,
        cor: Colors.green,
        telaDestino: LojistaProdutosScreen(uidLoja: _uidLoja),
      ));
    }

    // Nível 3: Config + Avaliações
    if (_nivel >= 3) {
      itens.add(const SizedBox(height: 15));
      itens.add(_buildMenuCard(
        context,
        titulo: 'Configurações da loja',
        subtitulo: 'Horários de funcionamento, nome e status',
        icone: Icons.store_mall_directory,
        cor: diPertinRoxo,
        telaDestino: LojistaConfigScreen(dadosAtuaisDaLoja: dados),
      ));
      itens.add(const SizedBox(height: 15));
      itens.add(_buildMenuCard(
        context,
        titulo: 'Avaliações de clientes',
        subtitulo: 'Feedbacks e notas da sua loja',
        icone: Icons.star,
        cor: Colors.amber,
        telaDestino: LojistaAvaliacoesScreen(uidLoja: _uidLoja),
      ));
    }

    return itens;
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
    final descricao = (dados['motivo_recusa_descricao'] ?? '').toString().trim();

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
                    Icon(Icons.info_outline,
                        color: Colors.red.shade700, size: 20),
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
              border: Border.all(
                color: diPertinRoxo.withValues(alpha: 0.25),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.event_available_outlined,
                    color: diPertinRoxo, size: 22),
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
    return Material(
      color: aberta ? Colors.green.shade50 : Colors.red.shade50,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              aberta ? Icons.storefront : Icons.store_mall_directory_outlined,
              size: 18,
              color: aberta ? Colors.green.shade800 : Colors.red.shade800,
            ),
            const SizedBox(width: 6),
            Text(
              aberta ? 'Loja aberta' : 'Loja fechada',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: aberta ? Colors.green.shade800 : Colors.red.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _celulaResumo({
    required String valor,
    required String legenda,
    required IconData icone,
    required Color cor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icone, color: cor, size: 28),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              valor,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: cor,
                height: 1.1,
              ),
            ),
            Text(
              legenda,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
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
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => telaDestino),
          );
        },
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icone, color: cor, size: 30),
                  ),
                  if (badgeCount != null && badgeCount > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        constraints: const BoxConstraints(minWidth: 20),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitulo,
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../constants/entregador_perfil_operacional.dart';
import '../../../services/conta_bloqueio_entregador_service.dart';
import '../../../services/entregador_perfil_operacional_service.dart';
import '../../../utils/entregador_voltar_perfil.dart';
import '../../../widgets/dialogo_confirmacao_perigo.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);

class EntregadorAreaPerigoScreen extends StatefulWidget {
  const EntregadorAreaPerigoScreen({
    super.key,
    this.abrirEmDesbloquear = false,
  });

  final bool abrirEmDesbloquear;

  @override
  State<EntregadorAreaPerigoScreen> createState() =>
      _EntregadorAreaPerigoScreenState();
}

class _EntregadorAreaPerigoScreenState extends State<EntregadorAreaPerigoScreen> {
  /// Evita rebuild do [StreamBuilder] enquanto a pilha de rotas está sendo desmontada.
  bool _saindoParaPerfil = false;
  bool _navegacaoPerfilEmAndamento = false;

  void _irParaMeuPerfil({String? mensagemSnackBar}) {
    if (!mounted || _navegacaoPerfilEmAndamento) return;
    _navegacaoPerfilEmAndamento = true;
    setState(() => _saindoParaPerfil = true);
    voltarMeuPerfilAposAcaoEntregador(
      context,
      mensagemSnackBar: mensagemSnackBar,
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.abrirEmDesbloquear) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return;
        FirebaseFirestore.instance.collection('users').doc(uid).get().then((s) {
          if (!mounted || !s.exists) return;
          final d = s.data() ?? {};
          if (ContaBloqueioEntregadorService.podeDesbloquearPeloProprioEntregador(
            d,
          )) {
            _confirmarDesbloqueio(d);
          }
        });
      });
    }
  }

  Future<void> _mostrarErro(String msg) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  Future<void> _comLoading(Future<void> Function() acao) async {
    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: CircularProgressIndicator(color: _roxo),
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    try {
      await acao();
    } finally {
      if (context.mounted && nav.canPop()) {
        nav.pop();
      }
    }
  }

  Future<void> _modalBloquearConta() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ModalEscolhaBloqueio(
        onTemporario: () {
          Navigator.pop(ctx);
          Future.microtask(() {
            if (mounted) _modalBloqueioTemporario();
          });
        },
        onDefinitivo: () {
          Navigator.pop(ctx);
          Future.microtask(() {
            if (mounted) _modalBloqueioDefinitivo();
          });
        },
      ),
    );
  }

  Future<void> _modalBloqueioTemporario() async {
    final draft = await showDialog<_DraftPausaTemporaria>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DialogoFormPausaTemporaria(),
    );
    if (!mounted || draft == null) return;
    // Deixa o diálogo do formulário (e seus controllers) sair da árvore antes do Sim/Não.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final confirmar = await mostrarDialogoConfirmacaoPerigo(
      context,
      titulo: 'Confirmar bloqueio do perfil de entregador',
      mensagem:
          'Tem certeza que deseja bloquear seu perfil de entregador? '
          'Você não poderá acessar o painel de entregas enquanto estiver bloqueado.',
      rotuloConfirmar: 'Sim, bloquear',
    );
    if (!confirmar || !mounted) return;

    try {
      await _comLoading(() async {
        await EntregadorPerfilOperacionalService.bloquearTemporario(
          dias: draft.dias,
          meses: draft.meses,
          motivo: draft.motivo,
        );
      });
      if (!mounted) return;
      _irParaMeuPerfil(mensagemSnackBar: 'Perfil de entregador pausado.');
    } catch (e) {
      await _mostrarErro(EntregadorPerfilOperacionalService.mensagemErro(e));
    }
  }

  Future<void> _modalBloqueioDefinitivo() async {
    final confirmar = await mostrarDialogoConfirmacaoPerigo(
      context,
      titulo: 'Confirmar bloqueio do perfil de entregador',
      mensagem:
          'Tem certeza que deseja bloquear seu perfil de entregador? '
          'Você não poderá acessar o painel de entregas enquanto estiver bloqueado.',
      rotuloConfirmar: 'Sim, bloquear',
      destrutivo: true,
    );
    if (!confirmar || !mounted) return;

    try {
      await _comLoading(() async {
        await EntregadorPerfilOperacionalService.bloquearDefinitivo();
      });
      if (!mounted) return;
      _irParaMeuPerfil(mensagemSnackBar: 'Perfil de entregador bloqueado.');
    } catch (e) {
      await _mostrarErro(EntregadorPerfilOperacionalService.mensagemErro(e));
    }
  }

  Future<void> _modalSolicitarExclusao() async {
    final confirmar = await mostrarDialogoConfirmacaoPerigo(
      context,
      titulo: 'Confirmar solicitação de exclusão',
      mensagem:
          'Tem certeza que deseja solicitar a exclusão do perfil de entregador? '
          'Sua conta de cliente continuará ativa normalmente. '
          'Você poderá criar um novo perfil de entregador somente após '
          '${EntregadorPerfilOperacional.diasCarenciaReingressoEntregador} dias corridos.',
      rotuloConfirmar: 'Sim, solicitar exclusão',
      destrutivo: true,
    );
    if (!confirmar || !mounted) return;

    try {
      await _comLoading(() async {
        await EntregadorPerfilOperacionalService.solicitarExclusaoPerfil();
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline, color: _roxo, size: 48),
          title: const Text('Solicitação enviada'),
          content: const Text(
            'Seu perfil de entregador foi bloqueado. Em até '
            '${EntregadorPerfilOperacional.diasCarenciaExclusaoPerfil} dias o perfil '
            'será removido automaticamente. Você continua usando o app como cliente.',
            style: TextStyle(height: 1.45),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      _irParaMeuPerfil();
    } catch (e) {
      await _mostrarErro(EntregadorPerfilOperacionalService.mensagemErro(e));
    }
  }

  Future<void> _confirmarDesbloqueio(Map<String, dynamic> dados) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desbloquear conta'),
        content: Text(
          ContaBloqueioEntregadorService.isBloqueioTemporarioTipo(dados)
              ? 'Sua pausa será encerrada e você poderá voltar a receber entregas.'
              : 'Seu bloqueio será removido e você poderá voltar a trabalhar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _roxo),
            child: const Text('Desbloquear'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await _comLoading(() async {
        await EntregadorPerfilOperacionalService.desbloquearConta();
      });
      if (!mounted) return;
      _irParaMeuPerfil(mensagemSnackBar: 'Perfil de entregador reativado.');
    } catch (e) {
      await _mostrarErro(EntregadorPerfilOperacionalService.mensagemErro(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text(
          'Área de Perigo',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _roxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _saindoParaPerfil
          ? const Center(child: CircularProgressIndicator(color: _roxo))
          : uid == null
          ? const Center(child: Text('Faça login para continuar.'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final d = snap.data!.data() ?? {};
                final bloqueado =
                    ContaBloqueioEntregadorService.estaBloqueadoParaOperacoes(
                  d,
                );
                final exclusao =
                    ContaBloqueioEntregadorService.ehExclusaoPerfilSolicitada(
                  d,
                );
                final podeDesbloquear =
                    ContaBloqueioEntregadorService
                        .podeDesbloquearPeloProprioEntregador(d);
                final fmt = DateFormat('dd/MM/yyyy HH:mm');

                return ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.red.shade50,
                                Colors.white,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.red.shade100),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                color: Colors.red.shade700,
                                size: 36,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'Ações sensíveis do seu perfil de entregador. '
                                  'Não afetam sua conta de cliente no aplicativo.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.45,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (bloqueado) ...[
                          const SizedBox(height: 16),
                          _StatusCard(
                            titulo: ContaBloqueioEntregadorService.rotuloTipoBloqueio(d),
                            subtitulo: exclusao
                                ? 'Exclusão em andamento'
                                : 'Conta bloqueada',
                            inicio: ContaBloqueioEntregadorService.dataInicioBloqueio(d),
                            fim: ContaBloqueioEntregadorService.dataFimBloqueio(d),
                            diasExclusao:
                                ContaBloqueioEntregadorService.diasRestantesExclusaoPerfil(d),
                            motivo: ContaBloqueioEntregadorService.textoMotivoBloqueio(d),
                            fmt: fmt,
                          ),
                        ],
                        const SizedBox(height: 24),
                        if (podeDesbloquear)
                          _AcaoPerigo(
                            icone: Icons.lock_open_rounded,
                            titulo: 'Desbloquear conta',
                            subtitulo: 'Reativar perfil de entregador agora',
                            cor: _roxo,
                            onTap: () => _confirmarDesbloqueio(d),
                          ),
                        if (!bloqueado) ...[
                          _AcaoPerigo(
                            icone: Icons.pause_circle_outline,
                            titulo: 'Bloquear conta',
                            subtitulo: 'Pausa temporária ou bloqueio definitivo',
                            cor: Colors.orange.shade800,
                            onTap: _modalBloquearConta,
                          ),
                          const SizedBox(height: 12),
                          _AcaoPerigo(
                            icone: Icons.person_remove_outlined,
                            titulo: 'Solicitar exclusão',
                            subtitulo: 'Remove apenas o perfil de entregador',
                            cor: Colors.red.shade800,
                            onTap: _modalSolicitarExclusao,
                          ),
                        ],
                        if (exclusao)
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: Text(
                              'A exclusão solicitada não pode ser cancelada pelo app. '
                              'Em caso de dúvida, fale com o suporte.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
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

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.titulo,
    required this.subtitulo,
    this.inicio,
    this.fim,
    this.diasExclusao,
    this.motivo,
    required this.fmt,
  });

  final String titulo;
  final String subtitulo;
  final DateTime? inicio;
  final DateTime? fim;
  final int? diasExclusao;
  final String? motivo;
  final DateFormat fmt;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitulo,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.red.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (inicio != null) ...[
            const SizedBox(height: 10),
            Text('Início: ${fmt.format(inicio!)}',
                style: TextStyle(color: Colors.grey.shade700)),
          ],
          if (fim != null) ...[
            Text('Término previsto: ${fmt.format(fim!)}',
                style: TextStyle(color: Colors.grey.shade700)),
          ],
          if (diasExclusao != null) ...[
            const SizedBox(height: 8),
            Text(
              diasExclusao! > 0
                  ? '$diasExclusao dia${diasExclusao == 1 ? '' : 's'} até a remoção do perfil'
                  : 'Remoção do perfil em processamento',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.amber.shade900,
              ),
            ),
          ],
          if (motivo != null && motivo!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(motivo!, style: const TextStyle(height: 1.4)),
          ],
        ],
      ),
    );
  }
}

class _AcaoPerigo extends StatelessWidget {
  const _AcaoPerigo({
    required this.icone,
    required this.titulo,
    required this.subtitulo,
    required this.cor,
    this.onTap,
  });

  final IconData icone;
  final String titulo;
  final String subtitulo;
  final Color cor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icone, color: cor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitulo,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

class _DraftPausaTemporaria {
  const _DraftPausaTemporaria({
    this.dias,
    this.meses,
    this.motivo,
  });

  final int? dias;
  final int? meses;
  final String? motivo;
}

/// Formulário de pausa — controllers vivem no [State] e são liberados no [dispose].
class _DialogoFormPausaTemporaria extends StatefulWidget {
  const _DialogoFormPausaTemporaria();

  @override
  State<_DialogoFormPausaTemporaria> createState() =>
      _DialogoFormPausaTemporariaState();
}

class _DialogoFormPausaTemporariaState extends State<_DialogoFormPausaTemporaria> {
  late final TextEditingController _quantidadeC;
  late final TextEditingController _motivoC;
  String _unidade = 'dias';

  @override
  void initState() {
    super.initState();
    _quantidadeC = TextEditingController(text: '7');
    _motivoC = TextEditingController();
  }

  @override
  void dispose() {
    _quantidadeC.dispose();
    _motivoC.dispose();
    super.dispose();
  }

  void _aoMudarUnidade(String nova) {
    if (_unidade == nova) return;
    setState(() {
      _unidade = nova;
      _quantidadeC.text = nova == 'dias' ? '7' : '1';
    });
  }

  void _continuar() {
    final n = int.tryParse(_quantidadeC.text.trim());
    if (n == null || n < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe um período válido.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final motivo = _motivoC.text.trim();
    Navigator.pop(
      context,
      _DraftPausaTemporaria(
        dias: _unidade == 'dias' ? n : null,
        meses: _unidade == 'meses' ? n : null,
        motivo: motivo.isEmpty ? null : motivo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bloqueio temporário'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Informe por quanto tempo deseja ficar sem trabalhar. '
              'Durante a pausa você não receberá entregas.',
              style: TextStyle(height: 1.45),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'dias', label: Text('Dias')),
                ButtonSegment(value: 'meses', label: Text('Meses')),
              ],
              selected: {_unidade},
              onSelectionChanged: (s) => _aoMudarUnidade(s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantidadeC,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: _unidade == 'dias'
                    ? 'Quantidade de dias'
                    : 'Quantidade de meses',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _motivoC,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _continuar,
          style: FilledButton.styleFrom(backgroundColor: _roxo),
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}

class _ModalEscolhaBloqueio extends StatelessWidget {
  const _ModalEscolhaBloqueio({
    required this.onTemporario,
    required this.onDefinitivo,
  });

  final VoidCallback onTemporario;
  final VoidCallback onDefinitivo;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Como deseja bloquear?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Escolha uma opção. Você poderá desbloquear depois na Área de Perigo.',
              style: TextStyle(color: Colors.grey.shade700, height: 1.4),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: _laranja.withValues(alpha: 0.15),
                child: const Icon(Icons.schedule_rounded, color: _laranja),
              ),
              title: const Text('Bloqueio temporário'),
              subtitle: const Text('Pausa por dias ou meses'),
              onTap: onTemporario,
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.red.shade50,
                child: Icon(Icons.block, color: Colors.red.shade700),
              ),
              title: const Text('Bloqueio definitivo'),
              subtitle: const Text('Até você desbloquear manualmente'),
              onTap: onDefinitivo,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}

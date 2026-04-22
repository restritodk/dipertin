import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class NotificacoesScreen extends StatefulWidget {
  const NotificacoesScreen({super.key});

  @override
  State<NotificacoesScreen> createState() => _NotificacoesScreenState();
}

class _NotificacoesScreenState extends State<NotificacoesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _tituloC = TextEditingController();
  final _mensagemC = TextEditingController();
  String _publicoAlvo = 'todos';
  String _cidadeSelecionada = 'Todas';
  bool _enviando = false;
  List<String> _cidades = ['Todas'];

  /// Modo seleção no histórico: checkboxes + exclusão em lote.
  bool _historicoModoSelecao = false;
  final Set<String> _historicoIdsMarcados = {};

  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index != 1) {
        _historicoModoSelecao = false;
        _historicoIdsMarcados.clear();
      }
      if (mounted) setState(() {});
    });
    _tituloC.addListener(() => setState(() {}));
    _mensagemC.addListener(() => setState(() {}));
    _carregarCidades();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _tituloC.dispose();
    _mensagemC.dispose();
    super.dispose();
  }

  Future<void> _carregarCidades() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').get();
      final set = <String>{'Todas'};
      for (final d in snap.docs) {
        final c = d.data()['cidade']?.toString().trim() ?? '';
        if (c.isNotEmpty) {
          set.add(c[0].toUpperCase() + c.substring(1).toLowerCase());
        }
      }
      final lista = set.toList()..sort();
      lista.remove('Todas');
      lista.insert(0, 'Todas');
      if (mounted) setState(() => _cidades = lista);
    } catch (_) {}
  }

  Future<void> _enviarNotificacao() async {
    if (_tituloC.text.trim().isEmpty || _mensagemC.text.trim().isEmpty) {
      _snack('Preencha título e mensagem.', erro: true);
      return;
    }
    setState(() => _enviando = true);
    try {
      await FirebaseFirestore.instance
          .collection('notificacoes_campanhas')
          .add({
        'titulo': _tituloC.text.trim(),
        'mensagem': _mensagemC.text.trim(),
        'publico_alvo': _publicoAlvo,
        'cidade': _cidadeSelecionada == 'Todas'
            ? 'todas'
            : _cidadeSelecionada.toLowerCase(),
        'status': 'pendente',
        'data_criacao': FieldValue.serverTimestamp(),
        'total_enviado': 0,
      });
      _tituloC.clear();
      _mensagemC.clear();
      setState(() {
        _publicoAlvo = 'todos';
        _cidadeSelecionada = 'Todas';
      });
      _snack('Notificação enfileirada com sucesso!');
      _tabController.animateTo(1);
    } catch (e) {
      _snack('Erro ao enviar: $e', erro: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: erro ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _labelPublico(String p) {
    switch (p) {
      case 'cliente':
        return 'Clientes';
      case 'lojista':
        return 'Lojistas';
      case 'entregador':
        return 'Entregadores';
      default:
        return 'Todos os usuários';
    }
  }

  Future<bool> _confirmarExclusaoHistorico({required int quantidade}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir do histórico?'),
        content: Text(
          quantidade == 1
              ? 'Esta campanha será removida permanentemente.'
              : '$quantidade registros serão removidos permanentemente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _excluirCampanhaUma(String docId) async {
    if (!await _confirmarExclusaoHistorico(quantidade: 1)) return;
    try {
      await FirebaseFirestore.instance
          .collection('notificacoes_campanhas')
          .doc(docId)
          .delete();
      if (mounted) {
        _historicoIdsMarcados.remove(docId);
        setState(() {});
      }
      _snack('Registro excluído.');
    } catch (e) {
      _snack('Erro ao excluir: $e', erro: true);
    }
  }

  Future<void> _excluirCampanhasVarias(List<String> ids) async {
    if (ids.isEmpty) return;
    if (!await _confirmarExclusaoHistorico(quantidade: ids.length)) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      final col = FirebaseFirestore.instance.collection('notificacoes_campanhas');
      for (final id in ids) {
        batch.delete(col.doc(id));
      }
      await batch.commit();
      if (mounted) {
        _historicoIdsMarcados.clear();
        _historicoModoSelecao = false;
        setState(() {});
      }
      _snack(ids.length == 1 ? 'Registro excluído.' : '${ids.length} registros excluídos.');
    } catch (e) {
      _snack('Erro ao excluir: $e', erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildNovaTab(), _buildHistoricoTab()],
            ),
          ),
        ],
      ),
      floatingActionButton: const BotaoSuporteFlutuante(),
    );
  }

  Widget _buildHeader() {
    return Material(
      color: Colors.white,
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notificações Push',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: _roxo,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Envie mensagens push para clientes, lojistas ou entregadores por cidade.',
                        style: TextStyle(
                          color: PainelAdminTheme.textoSecundario,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: _roxo,
            unselectedLabelColor: PainelAdminTheme.textoSecundario,
            indicatorColor: _laranja,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            tabs: const [
              Tab(icon: Icon(Icons.send_rounded), height: 72, text: 'Nova notificação'),
              Tab(icon: Icon(Icons.history_rounded), height: 72, text: 'Histórico'),
            ],
          ),
          Divider(height: 1, color: Colors.grey.shade200),
        ],
      ),
    );
  }

  Widget _buildNovaTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildFormulario()),
              const SizedBox(width: 24),
              Expanded(flex: 2, child: _buildPreview()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormulario() {
    final dec = InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF8F7FC),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _roxo, width: 1.5),
      ),
    );

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Configurar mensagem',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _roxo,
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _publicoAlvo,
              decoration: dec.copyWith(labelText: 'Público-alvo'),
              items: const [
                DropdownMenuItem(value: 'todos', child: Text('Todos os usuários')),
                DropdownMenuItem(value: 'cliente', child: Text('Clientes')),
                DropdownMenuItem(value: 'lojista', child: Text('Lojistas')),
                DropdownMenuItem(value: 'entregador', child: Text('Entregadores')),
              ],
              onChanged: (v) => setState(() => _publicoAlvo = v!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _cidadeSelecionada,
              decoration: dec.copyWith(labelText: 'Cidade'),
              items: _cidades
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _cidadeSelecionada = v!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tituloC,
              maxLength: 65,
              decoration:
                  dec.copyWith(labelText: 'Título (até 65 caracteres)'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _mensagemC,
              maxLines: 4,
              maxLength: 200,
              decoration: dec.copyWith(
                labelText: 'Mensagem (até 200 caracteres)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _enviando ? null : _enviarNotificacao,
              icon: _enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 20),
              label: Text(_enviando ? 'Enviando…' : 'Enviar notificação'),
              style: FilledButton.styleFrom(
                backgroundColor: _laranja,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final titulo = _tituloC.text.isEmpty ? 'Título da notificação' : _tituloC.text;
    final mensagem = _mensagemC.text.isEmpty
        ? 'Aqui aparece o texto da mensagem...'
        : _mensagemC.text;

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Preview',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _roxo,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _laranja,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.notifications,
                            color: Colors.white, size: 16),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'DiPertin',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'agora',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    titulo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mensagem,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _infoRow(
                Icons.people_outline_rounded, 'Público', _labelPublico(_publicoAlvo)),
            const SizedBox(height: 8),
            _infoRow(Icons.place_outlined, 'Cidade',
                _cidadeSelecionada == 'Todas' ? 'Todas as cidades' : _cidadeSelecionada),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String valor) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600),
        ),
        Expanded(
          child: Text(
            valor,
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildHistoricoTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notificacoes_campanhas')
          .orderBy('data_criacao', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final snapData = snap.data;
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
            snapData != null
                ? List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                    snapData.docs,
                  )
                : [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_none_rounded,
                    size: 56, color: _roxo.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text('Nenhuma notificação enviada ainda.',
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 16)),
              ],
            ),
          );
        }

        // Tristate Checkbox (value: null) quebra no Flutter Web — usar só bool.
        final todosMarcados =
            docs.isNotEmpty && _historicoIdsMarcados.length == docs.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Material(
                    color: const Color(0xFFF8F7FC),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: _historicoModoSelecao
                          ? Row(
                              children: [
                                Checkbox(
                                  value: todosMarcados,
                                  activeColor: _roxo,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _historicoIdsMarcados
                                          ..clear()
                                          ..addAll(docs.map((e) => e.id));
                                      } else {
                                        _historicoIdsMarcados.clear();
                                      }
                                    });
                                  },
                                ),
                                Expanded(
                                  child: Text(
                                    'Selecionar todos',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade800,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => setState(() {
                                    _historicoModoSelecao = false;
                                    _historicoIdsMarcados.clear();
                                  }),
                                  child: const Text('Cancelar'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFB91C1C),
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: _historicoIdsMarcados.isEmpty
                                      ? null
                                      : () => _excluirCampanhasVarias(
                                          _historicoIdsMarcados.toList(),
                                        ),
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      size: 20),
                                  label: Text(
                                    _historicoIdsMarcados.isEmpty
                                        ? 'Excluir'
                                        : 'Excluir (${_historicoIdsMarcados.length})',
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Icon(Icons.touch_app_outlined,
                                    size: 20, color: Colors.grey.shade600),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Exclua um item pelo ícone da lixeira ou selecione vários para apagar de uma vez.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade700,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => setState(
                                      () => _historicoModoSelecao = true),
                                  icon: const Icon(Icons.checklist_rounded,
                                      size: 20),
                                  label: const Text('Selecionar para excluir'),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(24),
                    itemCount: docs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final docSnap = docs[i];
                      final docId = docSnap.id;
                      final d = docSnap.data();
                      final status = d['status']?.toString() ?? 'pendente';
                      final ts = d['data_criacao'] as Timestamp?;
                      final data = ts != null
                          ? DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate())
                          : '—';
                      final total = d['total_enviado'] ?? 0;
                      final totalFalhas = d['total_falhas'] ?? 0;
                      final tokensRemovidos = d['tokens_invalidos_removidos'] ?? 0;
                      final usersComToken = d['total_users_com_token'] ?? 0;
                      final observacao = (d['observacao'] ?? '').toString();
                      final publico =
                          _labelPublico(d['publico_alvo'] ?? 'todos');
                      final cidadeRaw =
                          (d['cidade'] ?? 'todas').toString().toLowerCase();
                      final cidade = cidadeRaw == 'todas'
                          ? 'Todas as cidades'
                          : cidadeRaw.toUpperCase();

                      Color statusColor;
                      IconData statusIcon;
                      switch (status) {
                        case 'enviado':
                          statusColor = const Color(0xFF15803D);
                          statusIcon = Icons.check_circle_outline_rounded;
                          break;
                        case 'erro':
                          statusColor = const Color(0xFFB91C1C);
                          statusIcon = Icons.error_outline_rounded;
                          break;
                        default:
                          statusColor = _laranja;
                          statusIcon = Icons.schedule_rounded;
                      }

                      return Material(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: InkWell(
                          onTap: _historicoModoSelecao
                              ? () {
                                  setState(() {
                                    if (_historicoIdsMarcados.contains(docId)) {
                                      _historicoIdsMarcados.remove(docId);
                                    } else {
                                      _historicoIdsMarcados.add(docId);
                                    }
                                  });
                                }
                              : null,
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_historicoModoSelecao) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Checkbox(
                                      value: _historicoIdsMarcados
                                          .contains(docId),
                                      activeColor: _roxo,
                                      onChanged: (_) {
                                        setState(() {
                                          if (_historicoIdsMarcados
                                              .contains(docId)) {
                                            _historicoIdsMarcados.remove(docId);
                                          } else {
                                            _historicoIdsMarcados.add(docId);
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ],
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(statusIcon,
                                      color: statusColor, size: 24),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        d['titulo'] ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        d['mensagem'] ?? '',
                                        style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 13,
                                            height: 1.4),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          _chip(Icons.people_outline_rounded,
                                              publico, Colors.grey.shade700),
                                          _chip(Icons.place_outlined, cidade,
                                              Colors.grey.shade700),
                                          if (status == 'enviado')
                                            _chip(
                                                Icons.send_rounded,
                                                usersComToken > 0
                                                    ? '$total/$usersComToken aceitos'
                                                    : '$total enviados',
                                                const Color(0xFF15803D)),
                                          if (status == 'enviado' &&
                                              totalFalhas is num &&
                                              totalFalhas > 0)
                                            _chip(
                                                Icons.warning_amber_rounded,
                                                '$totalFalhas falhas',
                                                const Color(0xFFB45309)),
                                          if (status == 'enviado' &&
                                              tokensRemovidos is num &&
                                              tokensRemovidos > 0)
                                            _chip(
                                                Icons.cleaning_services_rounded,
                                                '$tokensRemovidos tokens limpos',
                                                Colors.grey.shade700),
                                          _chip(Icons.schedule_rounded, data,
                                              Colors.grey.shade500),
                                        ],
                                      ),
                                      if (observacao.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFEF3C7),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                                color: const Color(0xFFFDE68A)),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.info_outline_rounded,
                                                size: 14,
                                                color: Color(0xFF92400E),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  observacao,
                                                  style: const TextStyle(
                                                    fontSize: 11.5,
                                                    color: Color(0xFF92400E),
                                                    height: 1.35,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (!_historicoModoSelecao)
                                          IconButton(
                                            tooltip: 'Excluir',
                                            icon: Icon(
                                              Icons.delete_outline_rounded,
                                              color: Colors.grey.shade600,
                                            ),
                                            onPressed: () =>
                                                _excluirCampanhaUma(docId),
                                          ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: statusColor
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            status.toUpperCase(),
                                            style: TextStyle(
                                              color: statusColor,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

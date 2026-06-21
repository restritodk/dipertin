import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/marketing_leads_status.dart';
import '../services/marketing_leads_service.dart';
import '../theme/painel_admin_theme.dart';
import '../utils/csv_download.dart';

/// Definição de um campo do formulário de lead.
class LeadCampo {
  const LeadCampo({
    required this.chave,
    required this.label,
    this.obrigatorio = false,
    this.multiline = false,
    this.email = false,
    this.telefone = false,
    this.exibirNaLista = false,
  });

  final String chave;
  final String label;
  final bool obrigatorio;
  final bool multiline;
  final bool email;
  final bool telefone;

  /// Se entra na linha de subtítulo do card da lista.
  final bool exibirNaLista;
}

/// Configuração de um CRM de leads (lojistas ou entregadores).
class LeadConfig {
  const LeadConfig({
    required this.colecao,
    required this.titulo,
    required this.descricao,
    required this.icon,
    required this.campos,
    required this.chaveTitulo,
    required this.statusOrdem,
    required this.statusInfo,
    this.chaveWhatsapp,
  });

  final String colecao;
  final String titulo;
  final String descricao;
  final IconData icon;
  final List<LeadCampo> campos;

  /// Chave usada como título do card.
  final String chaveTitulo;

  /// Funil de status (ordem dos chips).
  final List<String> statusOrdem;
  final MarketingLeadStatusInfo Function(String?) statusInfo;

  /// Chave do campo de WhatsApp/telefone para botão de atalho.
  final String? chaveWhatsapp;
}

enum _ModoVis { pipeline, lista }

class LeadsBasePanel extends StatefulWidget {
  const LeadsBasePanel({super.key, required this.config});

  final LeadConfig config;

  @override
  State<LeadsBasePanel> createState() => _LeadsBasePanelState();
}

class _LeadsBasePanelState extends State<LeadsBasePanel> {
  static const Color _border = Color(0xFFE2E8F0);

  final TextEditingController _buscaCtrl = TextEditingController();
  String _busca = '';
  String _statusFiltro = '';
  _ModoVis _modo = _ModoVis.pipeline;

  LeadConfig get cfg => widget.config;

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _cabecalho(),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: MarketingLeadsService.stream(cfg.colecao),
            builder: (context, snap) {
              if (snap.hasError) {
                return _erroBox(snap.error.toString());
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data?.docs ?? const [];
              final filtrados = _filtrar(docs);
              final buscaFiltrados = _filtrar(docs, ignorarStatus: true);
              return _conteudo(docs, filtrados, buscaFiltrados);
            },
          ),
        ),
      ],
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filtrar(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    bool ignorarStatus = false,
  }) {
    final termo = _busca.trim().toLowerCase();
    return docs.where((d) {
      final m = d.data();
      if (!ignorarStatus &&
          _statusFiltro.isNotEmpty &&
          (m['status'] ?? MarketingLeadLojistaStatus.novo) != _statusFiltro) {
        return false;
      }
      if (termo.isEmpty) return true;
      for (final v in m.values) {
        if (v is String && v.toLowerCase().contains(termo)) return true;
      }
      return false;
    }).toList();
  }

  Widget _conteudo(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> todos,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> filtrados,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> buscaFiltrados,
  ) {
    final pipeline = _modo == _ModoVis.pipeline;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ferramentas(todos, pipeline ? buscaFiltrados : filtrados),
          const SizedBox(height: 14),
          if (!pipeline) ...[
            _funilChips(todos),
            const SizedBox(height: 16),
          ],
          Expanded(
            child: pipeline
                ? _pipeline(buscaFiltrados)
                : _listaScroll(filtrados),
          ),
        ],
      ),
    );
  }

  Widget _listaScroll(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> filtrados,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (filtrados.isEmpty)
                _vazio()
              else
                ...filtrados.map(_cardLead),
            ],
          ),
        ),
      ),
    );
  }

  // ——— Pipeline (Kanban) ———

  Widget _pipeline(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final porStatus = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{
      for (final s in cfg.statusOrdem) s: [],
    };
    for (final d in docs) {
      final s = (d.data()['status'] ?? cfg.statusOrdem.first).toString();
      (porStatus[s] ?? porStatus[cfg.statusOrdem.first]!).add(d);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in cfg.statusOrdem) _coluna(s, porStatus[s]!),
        ],
      ),
    );
  }

  Widget _coluna(
    String status,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final info = cfg.statusInfo(status);
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => _moverPara(d.data, status),
      builder: (context, candidatos, rejeitados) {
        final destacar = candidatos.isNotEmpty;
        return Container(
          width: 286,
          margin: const EdgeInsets.only(right: 14),
          decoration: BoxDecoration(
            color: destacar ? info.fundo : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: destacar ? info.cor : _border,
              width: destacar ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: info.cor.withValues(alpha: 0.25)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: info.cor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        info.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: PainelAdminTheme.dashboardInk,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: info.cor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${docs.length}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: info.cor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: docs.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            destacar ? 'Solte aqui' : 'Vazio',
                            style: TextStyle(
                              color: destacar
                                  ? info.cor
                                  : PainelAdminTheme.textoSecundario,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: docs.length,
                        itemBuilder: (context, i) =>
                            _pipelineCard(docs[i], info),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pipelineCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    MarketingLeadStatusInfo info,
  ) {
    final m = doc.data();
    final nome = (m[cfg.chaveTitulo] ?? m['nome'] ?? '—').toString();
    final contatoChave = cfg.chaveWhatsapp;
    final contato =
        contatoChave == null ? '' : (m[contatoChave] ?? '').toString().trim();
    final cidade = (m['cidade'] ?? '').toString().trim();

    final card = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 36,
            margin: const EdgeInsets.only(right: 10, top: 2),
            decoration: BoxDecoration(
              color: info.cor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: PainelAdminTheme.dashboardInk,
                    height: 1.25,
                  ),
                ),
                if (cidade.isNotEmpty || contato.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    [cidade, contato].where((e) => e.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: PainelAdminTheme.textoSecundario,
                    ),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 18),
            padding: EdgeInsets.zero,
            splashRadius: 18,
            onSelected: (op) {
              switch (op) {
                case 'editar':
                  _abrirFormulario(id: doc.id, dados: m);
                  break;
                case 'historico':
                  _abrirHistorico(doc.id, nome);
                  break;
                case 'whatsapp':
                  if (contato.isNotEmpty) _abrirWhatsapp(contato);
                  break;
                case 'excluir':
                  _confirmarExcluir(doc.id, nome);
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'editar',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_rounded, size: 19),
                  title: Text('Editar'),
                ),
              ),
              const PopupMenuItem(
                value: 'historico',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.history_rounded, size: 19),
                  title: Text('Histórico'),
                ),
              ),
              if (contato.isNotEmpty)
                const PopupMenuItem(
                  value: 'whatsapp',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.chat_rounded,
                        size: 19, color: Color(0xFF25D366)),
                    title: Text('WhatsApp'),
                  ),
                ),
              const PopupMenuItem(
                value: 'excluir',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline_rounded,
                      size: 19, color: Color(0xFFDC2626)),
                  title: Text('Excluir',
                      style: TextStyle(color: Color(0xFFDC2626))),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Draggable<String>(
      data: doc.id,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.95,
          child: SizedBox(width: 250, child: card),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: card),
      child: card,
    );
  }

  Future<void> _moverPara(String id, String novoStatus) async {
    try {
      await MarketingLeadsService.salvar(
        colecao: cfg.colecao,
        id: id,
        dados: {'status': novoStatus},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Movido para "${cfg.statusInfo(novoStatus).label}".'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao mover: $e')),
        );
      }
    }
  }

  Widget _cabecalho() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(28, 28, 28, 0),
      padding: const EdgeInsets.fromLTRB(22, 20, 18, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E1B4B), PainelAdminTheme.roxo, Color(0xFF7C3AED)],
          stops: [0, 0.45, 1],
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Icon(cfg.icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cfg.titulo,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  cfg.descricao,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    height: 1.45,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ferramentas(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> todos,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> filtrados,
  ) {
    return LayoutBuilder(builder: (context, c) {
      final estreito = c.maxWidth < 720;
      final busca = TextField(
        controller: _buscaCtrl,
        onChanged: (v) => setState(() => _busca = v),
        decoration: InputDecoration(
          hintText: 'Buscar por nome, cidade, contato...',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _busca.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _buscaCtrl.clear();
                    setState(() => _busca = '');
                  },
                ),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _border),
          ),
        ),
      );
      final acoes = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleModo(),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: filtrados.isEmpty
                ? null
                : () => _exportarCsv(filtrados),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Exportar CSV'),
            style: OutlinedButton.styleFrom(
              foregroundColor: PainelAdminTheme.roxo,
              side: BorderSide(
                  color: PainelAdminTheme.roxo.withValues(alpha: 0.4)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: () => _abrirFormulario(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Novo lead'),
            style: ElevatedButton.styleFrom(
              backgroundColor: PainelAdminTheme.roxo,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
          ),
        ],
      );

      if (estreito) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            busca,
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: acoes,
            ),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: busca),
          const SizedBox(width: 12),
          acoes,
        ],
      );
    });
  }

  Widget _toggleModo() {
    Widget botao(_ModoVis modo, IconData icon, String label) {
      final sel = _modo == modo;
      return InkWell(
        onTap: () => setState(() => _modo = modo),
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: sel ? PainelAdminTheme.roxo : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 17,
                  color: sel ? Colors.white : PainelAdminTheme.textoSecundario),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color:
                      sel ? Colors.white : PainelAdminTheme.textoSecundario,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          botao(_ModoVis.pipeline, Icons.view_kanban_rounded, 'Pipeline'),
          botao(_ModoVis.lista, Icons.view_list_rounded, 'Lista'),
        ],
      ),
    );
  }

  Widget _funilChips(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> todos,
  ) {
    int contar(String status) => todos
        .where((d) =>
            (d.data()['status'] ?? MarketingLeadLojistaStatus.novo) == status)
        .length;

    Widget chip(String label, String valor, int count, Color cor) {
      final sel = _statusFiltro == valor;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          selected: sel,
          label: Text('$label ($count)'),
          labelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: sel ? Colors.white : cor,
          ),
          selectedColor: cor,
          backgroundColor: cor.withValues(alpha: 0.10),
          side: BorderSide(color: cor.withValues(alpha: sel ? 1 : 0.25)),
          onSelected: (_) =>
              setState(() => _statusFiltro = sel ? '' : valor),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('Todos', '', todos.length, PainelAdminTheme.roxo),
          for (final s in cfg.statusOrdem)
            chip(cfg.statusInfo(s).label, s, contar(s), cfg.statusInfo(s).cor),
        ],
      ),
    );
  }

  Widget _cardLead(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data();
    final status = (m['status'] ?? cfg.statusOrdem.first).toString();
    final info = cfg.statusInfo(status);
    final nome = (m[cfg.chaveTitulo] ?? m['nome'] ?? '—').toString();

    final linhas = <String>[];
    for (final campo in cfg.campos) {
      if (!campo.exibirNaLista) continue;
      final v = (m[campo.chave] ?? '').toString().trim();
      if (v.isNotEmpty) linhas.add(v);
    }
    final whats = cfg.chaveWhatsapp == null
        ? ''
        : (m[cfg.chaveWhatsapp] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: PainelAdminTheme.roxo.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(cfg.icon, color: PainelAdminTheme.roxo, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: PainelAdminTheme.dashboardInk,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _chipStatus(info),
                  ],
                ),
                if (linhas.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    linhas.join('  ·  '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      color: PainelAdminTheme.textoSecundario,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (whats.isNotEmpty)
            IconButton(
              tooltip: 'Abrir WhatsApp',
              onPressed: () => _abrirWhatsapp(whats),
              icon: const Icon(Icons.chat_rounded,
                  color: Color(0xFF25D366), size: 22),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (op) {
              switch (op) {
                case 'editar':
                  _abrirFormulario(id: doc.id, dados: m);
                  break;
                case 'historico':
                  _abrirHistorico(doc.id, nome);
                  break;
                case 'excluir':
                  _confirmarExcluir(doc.id, nome);
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'editar',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_rounded, size: 20),
                  title: Text('Editar'),
                ),
              ),
              PopupMenuItem(
                value: 'historico',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.history_rounded, size: 20),
                  title: Text('Histórico de contato'),
                ),
              ),
              PopupMenuItem(
                value: 'excluir',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline_rounded,
                      size: 20, color: Color(0xFFDC2626)),
                  title: Text('Excluir',
                      style: TextStyle(color: Color(0xFFDC2626))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chipStatus(MarketingLeadStatusInfo info) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: info.fundo,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: info.cor.withValues(alpha: 0.3)),
      ),
      child: Text(
        info.label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: info.cor,
        ),
      ),
    );
  }

  Widget _vazio() {
    final temFiltro = _busca.isNotEmpty || _statusFiltro.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Icon(
            temFiltro ? Icons.search_off_rounded : cfg.icon,
            size: 44,
            color: PainelAdminTheme.textoSecundario,
          ),
          const SizedBox(height: 14),
          Text(
            temFiltro
                ? 'Nenhum lead encontrado'
                : 'Nenhum lead cadastrado ainda',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: PainelAdminTheme.dashboardInk,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            temFiltro
                ? 'Ajuste a busca ou os filtros de status.'
                : 'Use "Novo lead" para começar a captar parceiros.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
          if (temFiltro) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {
                _buscaCtrl.clear();
                setState(() {
                  _busca = '';
                  _statusFiltro = '';
                });
              },
              icon: const Icon(Icons.clear_all_rounded, size: 18),
              label: const Text('Limpar filtros'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _erroBox(String erro) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFDC2626), size: 40),
            const SizedBox(height: 12),
            Text(
              'Não foi possível carregar os leads.',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: PainelAdminTheme.dashboardInk,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              erro,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, color: PainelAdminTheme.textoSecundario),
            ),
          ],
        ),
      ),
    );
  }

  // ——— Ações ———

  Future<void> _abrirWhatsapp(String numero) async {
    final digits = numero.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    final comDdi = digits.length <= 11 ? '55$digits' : digits;
    final uri = Uri.parse('https://wa.me/$comDdi');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _exportarCsv(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final cabecalho = <String>[
      ...cfg.campos.map((c) => c.label),
      'Status',
      'Criado em',
    ];
    final linhas = <List<Object?>>[];
    for (final d in docs) {
      final m = d.data();
      final criado = m['criado_em'];
      linhas.add([
        ...cfg.campos.map((c) => m[c.chave] ?? ''),
        cfg.statusInfo(m['status']?.toString()).label,
        criado is Timestamp ? fmt.format(criado.toDate()) : '',
      ]);
    }
    final nomeArq =
        'leads_${cfg.colecao}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
    exportarCsv(cabecalho: cabecalho, linhas: linhas, filename: nomeArq);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exportação CSV gerada.')),
      );
    }
  }

  Future<void> _confirmarExcluir(String id, String nome) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lead'),
        content: Text('Excluir "$nome"? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MarketingLeadsService.excluir(
        colecao: cfg.colecao,
        id: id,
        nomeParaLog: nome,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lead excluído.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir: $e')),
        );
      }
    }
  }

  Future<void> _abrirFormulario({
    String? id,
    Map<String, dynamic>? dados,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _LeadFormDialog(config: cfg, id: id, dados: dados),
    );
  }

  Future<void> _abrirHistorico(String id, String nome) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _LeadHistoricoDialog(colecao: cfg.colecao, leadId: id, nome: nome),
    );
  }
}

// ——— Dialog de cadastro/edição ———

class _LeadFormDialog extends StatefulWidget {
  const _LeadFormDialog({required this.config, this.id, this.dados});

  final LeadConfig config;
  final String? id;
  final Map<String, dynamic>? dados;

  @override
  State<_LeadFormDialog> createState() => _LeadFormDialogState();
}

class _LeadFormDialogState extends State<_LeadFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _ctrls = {};
  late String _status;
  bool _salvando = false;

  LeadConfig get cfg => widget.config;

  @override
  void initState() {
    super.initState();
    for (final c in cfg.campos) {
      _ctrls[c.chave] =
          TextEditingController(text: (widget.dados?[c.chave] ?? '').toString());
    }
    _status =
        (widget.dados?['status'] ?? cfg.statusOrdem.first).toString();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _salvando = true);
    final dados = <String, dynamic>{
      for (final c in cfg.campos) c.chave: _ctrls[c.chave]!.text.trim(),
      'status': _status,
    };
    try {
      await MarketingLeadsService.salvar(
        colecao: cfg.colecao,
        id: widget.id,
        dados: dados,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.id == null ? 'Lead criado.' : 'Lead atualizado.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.id != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [PainelAdminTheme.roxo, Color(0xFF7C3AED)],
                ),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  Icon(cfg.icon, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      editando ? 'Editar lead' : 'Novo lead',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final campo in cfg.campos) ...[
                        _campo(campo),
                        const SizedBox(height: 14),
                      ],
                      _dropdownStatus(),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _salvando ? null : () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _salvando ? null : _salvar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: PainelAdminTheme.roxo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 14),
                    ),
                    child: _salvando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white),
                          )
                        : const Text('Salvar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo(LeadCampo campo) {
    return TextFormField(
      controller: _ctrls[campo.chave],
      maxLines: campo.multiline ? 3 : 1,
      keyboardType: campo.email
          ? TextInputType.emailAddress
          : campo.telefone
              ? TextInputType.phone
              : TextInputType.text,
      inputFormatters:
          campo.telefone ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(
        labelText: campo.label + (campo.obrigatorio ? ' *' : ''),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: (v) {
        final t = (v ?? '').trim();
        if (campo.obrigatorio && t.isEmpty) {
          return 'Campo obrigatório';
        }
        if (campo.email && t.isNotEmpty) {
          final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
          if (!ok) return 'E-mail inválido';
        }
        return null;
      },
    );
  }

  Widget _dropdownStatus() {
    return DropdownButtonFormField<String>(
      initialValue: _status,
      decoration: InputDecoration(
        labelText: 'Status no funil',
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: [
        for (final s in cfg.statusOrdem)
          DropdownMenuItem(
            value: s,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: cfg.statusInfo(s).cor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(cfg.statusInfo(s).label),
              ],
            ),
          ),
      ],
      onChanged: (v) => setState(() => _status = v ?? _status),
    );
  }
}

// ——— Dialog de histórico ———

class _LeadHistoricoDialog extends StatefulWidget {
  const _LeadHistoricoDialog({
    required this.colecao,
    required this.leadId,
    required this.nome,
  });

  final String colecao;
  final String leadId;
  final String nome;

  @override
  State<_LeadHistoricoDialog> createState() => _LeadHistoricoDialogState();
}

class _LeadHistoricoDialogState extends State<_LeadHistoricoDialog> {
  final _ctrl = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _adicionar() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty) return;
    setState(() => _enviando = true);
    try {
      await MarketingLeadsService.adicionarHistorico(
        colecao: widget.colecao,
        leadId: widget.leadId,
        texto: texto,
      );
      _ctrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [PainelAdminTheme.roxo, Color(0xFF7C3AED)],
                ),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Histórico de contato',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          widget.nome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Flexible(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: MarketingLeadsService.streamHistorico(
                  colecao: widget.colecao,
                  leadId: widget.leadId,
                ),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final docs = snap.data?.docs ?? const [];
                  if (docs.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'Nenhum registro ainda.\nAdicione a primeira anotação abaixo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: PainelAdminTheme.textoSecundario,
                              height: 1.4),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    itemCount: docs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final m = docs[i].data();
                      final ts = m['criado_em'];
                      final quando =
                          ts is Timestamp ? fmt.format(ts.toDate()) : '';
                      final autor =
                          (m['autor_email'] ?? 'Equipe').toString();
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (m['texto'] ?? '').toString(),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13.5,
                                height: 1.4,
                                color: PainelAdminTheme.dashboardInk,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$autor · $quando',
                              style: const TextStyle(
                                fontSize: 11,
                                color: PainelAdminTheme.textoSecundario,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Nova anotação de contato...',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _enviando ? null : _adicionar,
                    style: IconButton.styleFrom(
                      backgroundColor: PainelAdminTheme.roxo,
                    ),
                    icon: _enviando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

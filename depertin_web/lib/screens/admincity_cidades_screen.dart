import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:depertin_web/widgets/cidade_autocomplete_overlay.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// AdminCity › Cadastro de Cidades.
///
/// Coleção Firestore: `cidades_atendidas` (schema: nome, uf,
/// nome_normalizada, uf_normalizada, label, ativa, criado_em).
///
/// Fornece:
///   - Importação em massa de municípios do IBGE (callable
///     `adminCityImportarCidadesIbge`, marca `ativa: false` por padrão);
///   - CRUD manual (cadastro individual, editar, ativar/desativar, excluir);
///   - Paginação local (10 por página) para não sobrecarregar a tela;
///   - Busca full-text por nome/UF;
///   - Filtro por status (todas, ativas, inativas).
class AdminCityCidadesScreen extends StatefulWidget {
  const AdminCityCidadesScreen({super.key});

  @override
  State<AdminCityCidadesScreen> createState() => _AdminCityCidadesScreenState();
}

class _AdminCityCidadesScreenState extends State<AdminCityCidadesScreen> {
  static const _gradTopo = LinearGradient(
    colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA), Color(0xFFAB47BC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const _roxo = Color(0xFF6A1B9A);
  static const _laranja = Color(0xFFFF8F00);
  static const int _porPagina = 10;

  String _filtro = '';
  _FiltroStatus _filtroStatus = _FiltroStatus.todas;
  int _pagina = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F1FA),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHero(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildResumo(),
                  const SizedBox(height: 20),
                  _buildFiltros(),
                  const SizedBox(height: 18),
                  _buildLista(),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: const BotaoSuporteFlutuante(),
    );
  }

  Widget _buildHero() {
    return Container(
      decoration: const BoxDecoration(gradient: _gradTopo),
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.25)),
            ),
            child: const Icon(Icons.map_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Cadastro de Cidades',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Defina onde o DiPertin atende. Importe a base do IBGE ou cadastre individualmente.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.88),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: _abrirNovaCidade,
            icon:
                const Icon(Icons.add_location_alt_rounded, color: _roxo, size: 18),
            label: Text(
              'Nova cidade',
              style: GoogleFonts.plusJakartaSans(
                color: _roxo,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumo() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cidades_atendidas')
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final total = docs.length;
        final ativas = docs.where((d) {
          final m = d.data() as Map<String, dynamic>;
          return (m['ativa'] as bool?) ?? true;
        }).length;
        final ufs = docs.map((d) {
          final m = d.data() as Map<String, dynamic>;
          return (m['uf'] ?? '').toString();
        }).where((u) => u.isNotEmpty).toSet().length;

        return Row(
          children: [
            Expanded(
              child: _CardMetric(
                icon: Icons.location_city_rounded,
                cor: _roxo,
                titulo: 'Total de cidades',
                valor: '$total',
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _CardMetric(
                icon: Icons.check_circle_rounded,
                cor: Colors.green.shade700,
                titulo: 'Cidades ativas',
                valor: '$ativas',
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _CardMetric(
                icon: Icons.flag_rounded,
                cor: _laranja,
                titulo: 'Estados cobertos',
                valor: '$ufs',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFiltros() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: _roxo.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() {
                _filtro = v.trim();
                _pagina = 0;
              }),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Buscar por cidade ou UF…',
                hintStyle:
                    GoogleFonts.plusJakartaSans(color: Colors.grey.shade500),
                prefixIcon:
                    Icon(Icons.search_rounded, color: Colors.grey.shade600),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _ChipFiltro(
            label: 'Todas',
            selecionado: _filtroStatus == _FiltroStatus.todas,
            onTap: () => setState(() {
              _filtroStatus = _FiltroStatus.todas;
              _pagina = 0;
            }),
          ),
          const SizedBox(width: 6),
          _ChipFiltro(
            label: 'Ativas',
            cor: Colors.green.shade700,
            selecionado: _filtroStatus == _FiltroStatus.ativas,
            onTap: () => setState(() {
              _filtroStatus = _FiltroStatus.ativas;
              _pagina = 0;
            }),
          ),
          const SizedBox(width: 6),
          _ChipFiltro(
            label: 'Inativas',
            cor: Colors.grey.shade600,
            selecionado: _filtroStatus == _FiltroStatus.inativas,
            onTap: () => setState(() {
              _filtroStatus = _FiltroStatus.inativas;
              _pagina = 0;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildLista() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cidades_atendidas')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return _buildVazio(
            Icons.error_outline,
            'Erro ao carregar cidades',
            'Detalhe: ${snap.error}',
          );
        }
        var docs = snap.data?.docs ?? [];
        docs.sort((a, b) {
          final ma = a.data() as Map<String, dynamic>;
          final mb = b.data() as Map<String, dynamic>;
          final ufA = (ma['uf_normalizada'] ?? '').toString();
          final ufB = (mb['uf_normalizada'] ?? '').toString();
          final cmp = ufA.compareTo(ufB);
          if (cmp != 0) return cmp;
          final nA = (ma['nome_normalizada'] ?? '').toString();
          final nB = (mb['nome_normalizada'] ?? '').toString();
          return nA.compareTo(nB);
        });

        if (_filtroStatus != _FiltroStatus.todas) {
          final wantAtiva = _filtroStatus == _FiltroStatus.ativas;
          docs = docs.where((d) {
            final m = d.data() as Map<String, dynamic>;
            final ativa = (m['ativa'] as bool?) ?? true;
            return ativa == wantAtiva;
          }).toList();
        }

        if (_filtro.isNotEmpty) {
          final t = _filtro.toLowerCase();
          docs = docs.where((d) {
            final m = d.data() as Map<String, dynamic>;
            final n = (m['nome'] ?? '').toString().toLowerCase();
            final uf = (m['uf'] ?? '').toString().toLowerCase();
            final label = (m['label'] ?? '').toString().toLowerCase();
            return n.contains(t) || uf.contains(t) || label.contains(t);
          }).toList();
        }
        if (docs.isEmpty) {
          return _buildVazio(
            Icons.location_off_outlined,
            _filtro.isNotEmpty || _filtroStatus != _FiltroStatus.todas
                ? 'Nenhum resultado'
                : 'Nenhuma cidade cadastrada',
            _filtro.isNotEmpty
                ? 'Tente outro termo de busca.'
                : _filtroStatus != _FiltroStatus.todas
                    ? 'Troque o filtro para ver outras cidades.'
                    : 'Cadastre manualmente ou importe do IBGE.',
          );
        }

        final totalPaginas = (docs.length / _porPagina).ceil();
        if (_pagina >= totalPaginas) _pagina = totalPaginas - 1;
        if (_pagina < 0) _pagina = 0;
        final ini = _pagina * _porPagina;
        final fim =
            (ini + _porPagina) > docs.length ? docs.length : (ini + _porPagina);
        final paginaDocs = docs.sublist(ini, fim);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                'Exibindo ${ini + 1} – $fim de ${docs.length}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: paginaDocs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final d = paginaDocs[i];
                final m = d.data() as Map<String, dynamic>;
                return _LinhaCidade(
                  docId: d.id,
                  dados: m,
                  onEditar: () => _abrirEdicaoCidade(d.id, m),
                  onAlternarAtivo: () => _alternarAtivo(d.id, m),
                  onExcluir: () => _confirmarExcluir(d.id, m),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildPaginacao(totalPaginas),
          ],
        );
      },
    );
  }

  Widget _buildPaginacao(int totalPaginas) {
    if (totalPaginas <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.outlined(
          onPressed: _pagina > 0 ? () => setState(() => _pagina--) : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        const SizedBox(width: 8),
        ..._numerosPagina(totalPaginas).map(
          (n) {
            if (n < 0) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('…',
                    style: GoogleFonts.plusJakartaSans(
                        color: Colors.grey.shade500)),
              );
            }
            final ativo = n == _pagina;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: InkWell(
                onTap: () => setState(() => _pagina = n),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ativo ? _roxo : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: ativo ? _roxo : Colors.grey.shade300,
                    ),
                  ),
                  child: Text(
                    '${n + 1}',
                    style: GoogleFonts.plusJakartaSans(
                      color: ativo ? Colors.white : Colors.grey.shade800,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        IconButton.outlined(
          onPressed: _pagina < totalPaginas - 1
              ? () => setState(() => _pagina++)
              : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  /// Gera a sequência de números de página com reticências:
  /// ex. totalPaginas=20, current=5 → [0,-1,3,4,5,6,7,-1,19]
  List<int> _numerosPagina(int total) {
    if (total <= 7) return List.generate(total, (i) => i);
    final out = <int>[0];
    final left = (_pagina - 2).clamp(1, total - 2);
    final right = (_pagina + 2).clamp(1, total - 2);
    if (left > 1) out.add(-1);
    for (var i = left; i <= right; i++) {
      out.add(i);
    }
    if (right < total - 2) out.add(-1);
    out.add(total - 1);
    return out;
  }

  Widget _buildVazio(IconData icon, String titulo, String sub) {
    return Container(
      margin: const EdgeInsets.only(top: 30),
      padding: const EdgeInsets.all(42),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _roxo.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _roxo, size: 34),
          ),
          const SizedBox(height: 14),
          Text(
            titulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  // ============================ NOVA / EDIÇÃO ==========================
  Future<void> _abrirNovaCidade() => _abrirForm();

  Future<void> _abrirEdicaoCidade(String id, Map<String, dynamic> m) =>
      _abrirForm(docId: id, dados: m);

  Future<void> _abrirForm({
    String? docId,
    Map<String, dynamic>? dados,
  }) async {
    final isEdit = docId != null;
    final ctrlCidade = TextEditingController(
      text: dados?['label']?.toString() ?? '',
    );
    bool ativa = (dados?['ativa'] as bool?) ?? true;
    bool salvando = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          Future<void> salvar() async {
            final raw = ctrlCidade.text.trim();
            final partes = raw.split(RegExp(r'\s*[—–\-]\s*'));
            if (partes.length < 2 ||
                partes.last.trim().length != 2 ||
                partes.first.trim().isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                  backgroundColor: Colors.red,
                  content: Text(
                    'Selecione a cidade na lista (formato "Município — UF").',
                  ),
                ),
              );
              return;
            }
            final nome = partes.first.trim();
            final uf = partes.last.trim().toUpperCase();
            final nomeNorm = _normalizar(nome);
            final ufNorm = uf.toLowerCase();
            final label = '$nome — $uf';

            setSt(() => salvando = true);
            try {
              final col = FirebaseFirestore.instance
                  .collection('cidades_atendidas');
              if (!isEdit) {
                final ja = await col
                    .where('nome_normalizada', isEqualTo: nomeNorm)
                    .where('uf_normalizada', isEqualTo: ufNorm)
                    .limit(1)
                    .get();
                if (ja.docs.isNotEmpty) {
                  setSt(() => salvando = false);
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        backgroundColor: Colors.orange,
                        content: Text('Essa cidade já está cadastrada.'),
                      ),
                    );
                  }
                  return;
                }
              }
              final payload = <String, dynamic>{
                'nome': nome,
                'uf': uf,
                'nome_normalizada': nomeNorm,
                'uf_normalizada': ufNorm,
                'label': label,
                'ativa': ativa,
                'atualizado_em': FieldValue.serverTimestamp(),
              };
              if (isEdit) {
                await col.doc(docId).update(payload);
              } else {
                payload['criado_em'] = FieldValue.serverTimestamp();
                await col.add(payload);
              }
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.green,
                    content: Text(isEdit
                        ? 'Cidade atualizada com sucesso!'
                        : 'Cidade cadastrada com sucesso!'),
                  ),
                );
              }
            } catch (e) {
              setSt(() => salvando = false);
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.red,
                    content: Text('Erro: $e'),
                  ),
                );
              }
            }
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Container(
              width: 500,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    decoration: const BoxDecoration(gradient: _gradTopo),
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isEdit
                                ? Icons.edit_location_alt_rounded
                                : Icons.add_location_alt_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isEdit
                                    ? 'Editar cidade atendida'
                                    : 'Nova cidade atendida',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Selecione o município na lista IBGE.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.82),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CidadeAutocompleteOverlay(
                          controller: ctrlCidade,
                          label: 'Cidade — UF',
                          hint: 'Ex.: Rondonópolis',
                          helper:
                              'Comece a digitar e selecione na lista IBGE.',
                        ),
                        const SizedBox(height: 18),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFFAF7FC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: SwitchListTile(
                            value: ativa,
                            onChanged: (v) => setSt(() => ativa = v),
                            activeColor: _laranja,
                            title: Text(
                              'Cidade ativa',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              ativa
                                  ? 'Aparecerá como opção no cadastro de usuários e anúncios.'
                                  : 'Ficará oculta no cadastro de usuários.',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed:
                              salvando ? null : () => Navigator.pop(ctx),
                          child: Text(
                            'Cancelar',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: salvando ? null : salvar,
                          icon: salvando
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_rounded,
                                  color: Colors.white, size: 18),
                          label: Text(
                            isEdit ? 'Salvar' : 'Cadastrar',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _laranja,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _alternarAtivo(String id, Map<String, dynamic> m) async {
    final atual = (m['ativa'] as bool?) ?? true;
    try {
      await FirebaseFirestore.instance
          .collection('cidades_atendidas')
          .doc(id)
          .update({
        'ativa': !atual,
        'atualizado_em': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Erro: $e'),
        ),
      );
    }
  }

  Future<void> _confirmarExcluir(String id, Map<String, dynamic> m) async {
    final label = m['label']?.toString() ?? '${m['nome']} — ${m['uf']}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
            const SizedBox(width: 10),
            Text(
              'Excluir cidade?',
              style:
                  GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(
          'A cidade "$label" será removida da lista de cidades atendidas.',
          style: GoogleFonts.plusJakartaSans(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('cidades_atendidas')
          .doc(id)
          .delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Cidade excluída.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Erro: $e'),
        ),
      );
    }
  }

  static String _normalizar(String s) {
    const com = 'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ';
    const sem = 'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN';
    final buf = StringBuffer();
    for (final ch in s.split('')) {
      final i = com.indexOf(ch);
      buf.write(i >= 0 ? sem[i] : ch);
    }
    return buf
        .toString()
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}

// =====================================================================
// ENUM / WIDGETS INTERNOS
// =====================================================================
enum _FiltroStatus { todas, ativas, inativas }

class _ChipFiltro extends StatelessWidget {
  final String label;
  final bool selecionado;
  final Color? cor;
  final VoidCallback onTap;
  const _ChipFiltro({
    required this.label,
    required this.selecionado,
    required this.onTap,
    this.cor,
  });

  static const _roxo = Color(0xFF6A1B9A);

  @override
  Widget build(BuildContext context) {
    final c = cor ?? _roxo;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selecionado ? c : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selecionado ? c : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selecionado ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}

class _CardMetric extends StatelessWidget {
  final IconData icon;
  final Color cor;
  final String titulo;
  final String valor;
  const _CardMetric({
    required this.icon,
    required this.cor,
    required this.titulo,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: cor.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: cor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: cor, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha enxuta para a lista paginada — uma linha por cidade.
class _LinhaCidade extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> dados;
  final VoidCallback onEditar;
  final VoidCallback onAlternarAtivo;
  final VoidCallback onExcluir;

  const _LinhaCidade({
    required this.docId,
    required this.dados,
    required this.onEditar,
    required this.onAlternarAtivo,
    required this.onExcluir,
  });

  static const _roxo = Color(0xFF6A1B9A);
  static const _laranja = Color(0xFFFF8F00);

  @override
  Widget build(BuildContext context) {
    final nome = dados['nome']?.toString() ?? '—';
    final uf = dados['uf']?.toString() ?? '—';
    final ativa = (dados['ativa'] as bool?) ?? true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ativa ? _roxo.withOpacity(0.12) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ativa ? _roxo.withOpacity(0.1) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.location_city_rounded,
              color: ativa ? _roxo : Colors.grey.shade500,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    nome,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _laranja.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    uf,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: _laranja,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: ativa ? Colors.green.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: ativa ? Colors.green.shade200 : Colors.grey.shade300,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  ativa
                      ? Icons.check_circle_rounded
                      : Icons.pause_circle_filled_rounded,
                  size: 11,
                  color: ativa ? Colors.green.shade700 : Colors.grey.shade600,
                ),
                const SizedBox(width: 3),
                Text(
                  ativa ? 'Ativa' : 'Inativa',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: ativa
                        ? Colors.green.shade700
                        : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Editar',
            onPressed: onEditar,
            icon: Icon(Icons.edit_outlined,
                color: Colors.blue.shade600, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: ativa ? 'Desativar' : 'Ativar',
            onPressed: onAlternarAtivo,
            icon: Icon(
              ativa ? Icons.pause_circle_outline : Icons.play_circle_outline,
              color: ativa
                  ? Colors.orange.shade700
                  : Colors.green.shade700,
              size: 18,
            ),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Excluir',
            onPressed: onExcluir,
            icon: Icon(Icons.delete_outline,
                color: Colors.red.shade400, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

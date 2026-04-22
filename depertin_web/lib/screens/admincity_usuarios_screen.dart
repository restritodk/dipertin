import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/navigation/painel_navigation_scope.dart';
import 'package:depertin_web/services/firebase_functions_config.dart';
import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:depertin_web/widgets/cidade_atendida_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// AdminCity › Cadastro de Usuários.
///
/// CRUD de gerentes regionais (role = `master_city`) via Cloud Functions:
///   - `adminCityCadastrarUsuario`
///   - `adminCityAtualizarUsuario`
///   - `adminCityBloquearUsuario`
///   - `adminCityExcluirUsuario`
///
/// A cidade é escolhida de um dropdown alimentado pela coleção
/// `cidades_atendidas` (gerenciada na tela "Cadastro de Cidades").
class AdminCityUsuariosScreen extends StatefulWidget {
  const AdminCityUsuariosScreen({super.key});

  @override
  State<AdminCityUsuariosScreen> createState() =>
      _AdminCityUsuariosScreenState();
}

class _AdminCityUsuariosScreenState extends State<AdminCityUsuariosScreen> {
  static const _gradTopo = LinearGradient(
    colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA), Color(0xFFAB47BC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const _roxo = Color(0xFF6A1B9A);
  static const _laranja = Color(0xFFFF8F00);
  static const int _porPagina = 10;

  String _filtro = '';
  int _pagina = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F1FA),
      body: Column(
        children: [
          _buildHero(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildBusca(),
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
      padding: const EdgeInsets.fromLTRB(32, 30, 32, 28),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.25)),
            ),
            child: const Icon(Icons.supervisor_account_rounded,
                color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Cadastro de Usuários',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Gerentes regionais (AdminCity) com acesso ao painel operacional. Eles recebem um e-mail com os dados de acesso no momento do cadastro.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    color: Colors.white.withOpacity(0.88),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          ElevatedButton.icon(
            onPressed: _abrirNovoCadastro,
            icon: const Icon(Icons.person_add_rounded,
                color: _roxo, size: 20),
            label: Text(
              'Novo cadastro',
              style: GoogleFonts.plusJakartaSans(
                color: _roxo,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 22, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusca() {
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        onChanged: (v) => setState(() {
          _filtro = v.trim();
          _pagina = 0;
        }),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: 'Buscar por nome, e-mail, telefone ou cidade…',
          hintStyle:
              GoogleFonts.plusJakartaSans(color: Colors.grey.shade500),
          prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade600),
        ),
      ),
    );
  }

  Widget _buildLista() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('tipoUsuario', isEqualTo: 'master_city')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return _Vazio(
            icon: Icons.error_outline,
            titulo: 'Erro ao listar usuários',
            sub: '${snap.error}',
          );
        }
        var docs = snap.data?.docs ?? [];
        if (_filtro.isNotEmpty) {
          final t = _filtro.toLowerCase();
          docs = docs.where((d) {
            final m = d.data() as Map<String, dynamic>;
            final nome = (m['nome'] ?? m['nome_completo'] ?? '')
                .toString()
                .toLowerCase();
            final email = (m['email'] ?? '').toString().toLowerCase();
            final tel = (m['telefone'] ?? '').toString().toLowerCase();
            final cidade = (m['cidade'] ?? '').toString().toLowerCase();
            return nome.contains(t) ||
                email.contains(t) ||
                tel.contains(t) ||
                cidade.contains(t);
          }).toList();
        }
        if (docs.isEmpty) {
          return _Vazio(
            icon: Icons.group_add_outlined,
            titulo: _filtro.isEmpty
                ? 'Nenhum AdminCity cadastrado'
                : 'Nenhum resultado para "$_filtro"',
            sub: _filtro.isEmpty
                ? 'Cadastre o primeiro gerente regional para começar.'
                : 'Tente outro termo de busca.',
            cta: _filtro.isEmpty
                ? ElevatedButton.icon(
                    onPressed: _abrirNovoCadastro,
                    icon: const Icon(Icons.person_add_rounded,
                        color: Colors.white, size: 18),
                    label: Text(
                      'Novo cadastro',
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
                  )
                : null,
          );
        }

        final totalPaginas = (docs.length / _porPagina).ceil();
        if (_pagina >= totalPaginas) _pagina = totalPaginas - 1;
        if (_pagina < 0) _pagina = 0;
        final ini = _pagina * _porPagina;
        final fim = (ini + _porPagina) > docs.length
            ? docs.length
            : (ini + _porPagina);
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
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final d = paginaDocs[i];
                final m = d.data() as Map<String, dynamic>;
                return _CardUsuario(
                  uid: d.id,
                  dados: m,
                  onEditar: () => _abrirEdicao(d.id, m),
                  onBloquear: () => _confirmarBloqueio(d.id, m),
                  onExcluir: () => _confirmarExclusao(d.id, m),
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
    final numeros = _numerosPagina(totalPaginas);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.outlined(
          onPressed: _pagina > 0 ? () => setState(() => _pagina--) : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        const SizedBox(width: 8),
        ...numeros.map((n) {
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
        }),
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

  // ========================== FLUXO: NOVO CADASTRO =======================
  Future<void> _abrirNovoCadastro() async {
    final cidades = await _carregarCidadesAtivas();
    if (!mounted) return;
    if (cidades.isEmpty) {
      _showCta(
        titulo: 'Cadastre uma cidade primeiro',
        mensagem:
            'Para cadastrar um AdminCity, você precisa ter ao menos uma cidade atendida ativa. Cadastre em "AdminCity › Cadastro de Cidades".',
        textoCta: 'Ir para Cadastro de Cidades',
        onCta: () {
          context.navegarPainel('/admincity_cidades');
        },
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _FormUsuarioDialog(cidades: cidades),
    );
  }

  Future<void> _abrirEdicao(String uid, Map<String, dynamic> dados) async {
    final cidades = await _carregarCidadesAtivas();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _FormUsuarioDialog(
        cidades: cidades,
        editarUid: uid,
        dadosAtuais: dados,
      ),
    );
  }

  Future<List<_CidadeOpcao>> _carregarCidadesAtivas() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('cidades_atendidas')
          .where('ativa', isEqualTo: true)
          .get();
      final lista = snap.docs.map((d) {
        final m = d.data();
        return _CidadeOpcao(
          label: (m['label'] ?? '${m['nome']} — ${m['uf']}').toString(),
          nome: (m['nome'] ?? '').toString(),
          uf: (m['uf'] ?? '').toString(),
          nomeNorm: (m['nome_normalizada'] ?? '').toString(),
          ufNorm: (m['uf_normalizada'] ?? '').toString(),
        );
      }).toList()
        ..sort((a, b) => a.label.compareTo(b.label));
      return lista;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Falha ao carregar cidades: $e'),
          ),
        );
      }
      return [];
    }
  }

  void _showCta({
    required String titulo,
    required String mensagem,
    required String textoCta,
    required VoidCallback onCta,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: _laranja),
            const SizedBox(width: 10),
            Text(
              titulo,
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(
          mensagem,
          style: GoogleFonts.plusJakartaSans(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onCta();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _laranja,
              foregroundColor: Colors.white,
            ),
            child: Text(textoCta),
          ),
        ],
      ),
    );
  }

  // =============================== BLOQUEIO ==============================
  Future<void> _confirmarBloqueio(String uid, Map<String, dynamic> d) async {
    final bloqueadoAtual = (d['bloqueado'] as bool?) ?? false;
    final bloquear = !bloqueadoAtual;
    final nome = (d['nome'] ?? d['nome_completo'] ?? 'usuário').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(
              bloquear ? Icons.block : Icons.lock_open_rounded,
              color: bloquear ? Colors.red : Colors.green,
            ),
            const SizedBox(width: 10),
            Text(bloquear ? 'Bloquear acesso?' : 'Reativar acesso?',
                style:
                    GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(
          bloquear
              ? '$nome não poderá mais acessar o painel enquanto estiver bloqueado. Deseja continuar?'
              : '$nome poderá voltar a acessar o painel. Deseja reativar o acesso?',
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
              backgroundColor: bloquear ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(bloquear ? 'Bloquear' : 'Reativar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await callFirebaseFunctionSafe(
        'adminCityBloquearUsuario',
        parameters: {'uid': uid, 'bloquear': bloquear},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text(bloquear ? 'Usuário bloqueado.' : 'Usuário reativado.'),
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

  // =============================== EXCLUSÃO ==============================
  Future<void> _confirmarExclusao(String uid, Map<String, dynamic> d) async {
    final nome = (d['nome'] ?? d['nome_completo'] ?? 'usuário').toString();
    final confirmaCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red),
              const SizedBox(width: 10),
              Text('Excluir usuário?',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700, color: Colors.red)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Esta ação é irreversível. A conta de $nome será apagada completamente (Firebase Auth + perfil).',
                style: GoogleFonts.plusJakartaSans(),
              ),
              const SizedBox(height: 14),
              Text(
                'Digite EXCLUIR para confirmar:',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: confirmaCtrl,
                onChanged: (_) => setSt(() {}),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'EXCLUIR',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: confirmaCtrl.text.trim().toUpperCase() == 'EXCLUIR'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Excluir definitivamente'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await callFirebaseFunctionSafe(
        'adminCityExcluirUsuario',
        parameters: {'uid': uid},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Usuário excluído.'),
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
}

// =====================================================================
// MODELOS / WIDGETS
// =====================================================================
class _CidadeOpcao {
  final String label;
  final String nome;
  final String uf;
  final String nomeNorm;
  final String ufNorm;
  const _CidadeOpcao({
    required this.label,
    required this.nome,
    required this.uf,
    required this.nomeNorm,
    required this.ufNorm,
  });
}

class _CardUsuario extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> dados;
  final VoidCallback onEditar;
  final VoidCallback onBloquear;
  final VoidCallback onExcluir;

  const _CardUsuario({
    required this.uid,
    required this.dados,
    required this.onEditar,
    required this.onBloquear,
    required this.onExcluir,
  });

  static const _roxo = Color(0xFF6A1B9A);

  @override
  Widget build(BuildContext context) {
    final nome =
        (dados['nome'] ?? dados['nome_completo'] ?? 'Sem nome').toString();
    final email = (dados['email'] ?? '—').toString();
    final tel = (dados['telefone'] ?? '').toString();
    final cidade = (dados['cidade'] ?? '—').toString();
    final uf = (dados['uf'] ?? '').toString();
    final bloqueado = (dados['bloqueado'] as bool?) ?? false;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: bloqueado
              ? Colors.red.withOpacity(0.25)
              : _roxo.withOpacity(0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: bloqueado
                    ? [Colors.red.shade300, Colors.red.shade400]
                    : const [Color(0xFF8E24AA), Color(0xFF6A1B9A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                (nome.isNotEmpty ? nome[0] : '?').toUpperCase(),
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Coluna dados
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        nome,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: bloqueado
                            ? Colors.red.shade50
                            : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: bloqueado
                              ? Colors.red.shade200
                              : Colors.green.shade200,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            bloqueado
                                ? Icons.block
                                : Icons.check_circle_rounded,
                            size: 11,
                            color: bloqueado
                                ? Colors.red.shade700
                                : Colors.green.shade700,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            bloqueado ? 'Bloqueado' : 'Ativo',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: bloqueado
                                  ? Colors.red.shade700
                                  : Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    _ChipInfo(icon: Icons.email_outlined, texto: email),
                    if (tel.isNotEmpty)
                      _ChipInfo(icon: Icons.phone_outlined, texto: tel),
                    _ChipInfo(
                      icon: Icons.location_city_outlined,
                      texto: uf.isNotEmpty ? '$cidade • $uf' : cidade,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Ações (ícones)
          IconButton(
            tooltip: 'Editar',
            onPressed: onEditar,
            icon: Icon(Icons.edit_outlined,
                color: Colors.blue.shade600, size: 20),
          ),
          IconButton(
            tooltip: bloqueado ? 'Reativar' : 'Bloquear',
            onPressed: onBloquear,
            icon: Icon(
              bloqueado ? Icons.lock_open_rounded : Icons.block,
              color: bloqueado
                  ? Colors.green.shade600
                  : Colors.orange.shade700,
              size: 20,
            ),
          ),
          IconButton(
            tooltip: 'Excluir',
            onPressed: onExcluir,
            icon: Icon(Icons.delete_outline,
                color: Colors.red.shade400, size: 20),
          ),
        ],
      ),
    );
  }
}

class _ChipInfo extends StatelessWidget {
  final IconData icon;
  final String texto;
  const _ChipInfo({required this.icon, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Text(
          texto,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12.5,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}

class _Vazio extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String sub;
  final Widget? cta;
  const _Vazio({
    required this.icon,
    required this.titulo,
    required this.sub,
    this.cta,
  });

  static const _roxo = Color(0xFF6A1B9A);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 40),
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _roxo.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _roxo, size: 38),
          ),
          const SizedBox(height: 16),
          Text(
            titulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
          if (cta != null) ...[
            const SizedBox(height: 18),
            cta!,
          ],
        ],
      ),
    );
  }
}

// =====================================================================
// DIALOG — Formulário de cadastro/edição
// =====================================================================
class _FormUsuarioDialog extends StatefulWidget {
  final List<_CidadeOpcao> cidades;
  final String? editarUid;
  final Map<String, dynamic>? dadosAtuais;

  const _FormUsuarioDialog({
    required this.cidades,
    this.editarUid,
    this.dadosAtuais,
  });

  @override
  State<_FormUsuarioDialog> createState() => _FormUsuarioDialogState();
}

class _FormUsuarioDialogState extends State<_FormUsuarioDialog> {
  static const _gradTopo = LinearGradient(
    colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA), Color(0xFFAB47BC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const _laranja = Color(0xFFFF8F00);

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeC;
  late final TextEditingController _telC;
  late final TextEditingController _emailC;
  final _senhaC = TextEditingController();
  final _senha2C = TextEditingController();
  _CidadeOpcao? _cidade;
  bool _obs1 = true;
  bool _obs2 = true;
  bool _salvando = false;

  bool get _isEdicao => widget.editarUid != null;

  @override
  void initState() {
    super.initState();
    final d = widget.dadosAtuais;
    _nomeC = TextEditingController(
      text: (d?['nome'] ?? d?['nome_completo'] ?? '').toString(),
    );
    _telC = TextEditingController(text: (d?['telefone'] ?? '').toString());
    _emailC = TextEditingController(text: (d?['email'] ?? '').toString());
    if (_isEdicao && d != null) {
      final cn = (d['cidade_normalizada'] ?? '').toString();
      final un = (d['uf_normalizado'] ?? '').toString();
      for (final c in widget.cidades) {
        if (c.nomeNorm == cn && c.ufNorm == un) {
          _cidade = c;
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _nomeC.dispose();
    _telC.dispose();
    _emailC.dispose();
    _senhaC.dispose();
    _senha2C.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_cidade == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Selecione a cidade atendida.'),
        ),
      );
      return;
    }
    if (!_isEdicao) {
      if (_senhaC.text.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('A senha precisa ter pelo menos 6 caracteres.'),
          ),
        );
        return;
      }
      if (_senhaC.text != _senha2C.text) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('As senhas não coincidem.'),
          ),
        );
        return;
      }
    }

    setState(() => _salvando = true);
    try {
      if (_isEdicao) {
        await callFirebaseFunctionSafe(
          'adminCityAtualizarUsuario',
          parameters: {
            'uid': widget.editarUid,
            'nome': _nomeC.text.trim(),
            'telefone': _telC.text.trim(),
            'cidadeLabel': _cidade!.label,
            'cidadeUf': _cidade!.uf,
            'cidadeNorm': _cidade!.nomeNorm,
            'ufNorm': _cidade!.ufNorm,
          },
        );
      } else {
        await callFirebaseFunctionSafe(
          'adminCityCadastrarUsuario',
          parameters: {
            'nome': _nomeC.text.trim(),
            'telefone': _telC.text.trim(),
            'email': _emailC.text.trim(),
            'senha': _senhaC.text,
            'cidadeLabel': _cidade!.label,
            'cidadeUf': _cidade!.uf,
            'cidadeNorm': _cidade!.nomeNorm,
            'ufNorm': _cidade!.ufNorm,
          },
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text(
            _isEdicao
                ? 'Usuário atualizado com sucesso!'
                : 'Usuário cadastrado! Um e-mail de confirmação foi enviado.',
          ),
        ),
      );
    } catch (e) {
      setState(() => _salvando = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Erro: ${e.toString().replaceAll('Exception: ', '')}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 520,
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
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _campo(
                        controller: _nomeC,
                        label: 'Nome completo',
                        icon: Icons.person_outline_rounded,
                        validator: (v) => (v ?? '').trim().length < 3
                            ? 'Informe o nome.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _campo(
                        controller: _telC,
                        label: 'Telefone',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      CidadeAtendidaPicker(
                        selecionada: _cidade == null
                            ? null
                            : CidadePickerItem(
                                label: _cidade!.label,
                                nome: _cidade!.nome,
                                uf: _cidade!.uf,
                                nomeNorm: _cidade!.nomeNorm,
                                ufNorm: _cidade!.ufNorm,
                              ),
                        todas: widget.cidades
                            .map((c) => CidadePickerItem(
                                  label: c.label,
                                  nome: c.nome,
                                  uf: c.uf,
                                  nomeNorm: c.nomeNorm,
                                  ufNorm: c.ufNorm,
                                ))
                            .toList(),
                        onSelecionada: (sel) {
                          final original = widget.cidades.firstWhere(
                            (c) =>
                                c.nomeNorm == sel.nomeNorm &&
                                c.ufNorm == sel.ufNorm,
                            orElse: () => _CidadeOpcao(
                              label: sel.label,
                              nome: sel.nome,
                              uf: sel.uf,
                              nomeNorm: sel.nomeNorm,
                              ufNorm: sel.ufNorm,
                            ),
                          );
                          setState(() => _cidade = original);
                        },
                      ),
                      const SizedBox(height: 12),
                      _campo(
                        controller: _emailC,
                        label: 'E-mail',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_isEdicao,
                        validator: (v) {
                          if (_isEdicao) return null;
                          final t = (v ?? '').trim();
                          if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(t)) {
                            return 'E-mail inválido.';
                          }
                          return null;
                        },
                      ),
                      if (!_isEdicao) ...[
                        const SizedBox(height: 12),
                        _campo(
                          controller: _senhaC,
                          label: 'Senha (mín. 6 caracteres)',
                          icon: Icons.lock_outline,
                          obscure: _obs1,
                          trailing: IconButton(
                            icon: Icon(_obs1
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obs1 = !_obs1),
                          ),
                          validator: (v) => (v ?? '').length < 6
                              ? 'Mínimo de 6 caracteres.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _campo(
                          controller: _senha2C,
                          label: 'Confirmar senha',
                          icon: Icons.lock_outline,
                          obscure: _obs2,
                          trailing: IconButton(
                            icon: Icon(_obs2
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obs2 = !_obs2),
                          ),
                          validator: (v) => v != _senhaC.text
                              ? 'As senhas não coincidem.'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _laranja.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: _laranja.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.mark_email_read_outlined,
                                  color: _laranja, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'O usuário receberá um e-mail com os dados de acesso ao painel.',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12.5,
                                    color: Colors.grey.shade800,
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
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _salvando ? null : () => Navigator.pop(context),
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
                    onPressed: _salvando ? null : _salvar,
                    icon: _salvando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(
                            _isEdicao
                                ? Icons.save_rounded
                                : Icons.person_add_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                    label: Text(
                      _isEdicao ? 'Salvar alterações' : 'Cadastrar',
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
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(gradient: _gradTopo),
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _isEdicao
                  ? Icons.manage_accounts_rounded
                  : Icons.person_add_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isEdicao ? 'Editar AdminCity' : 'Novo AdminCity',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _isEdicao
                      ? 'Atualize os dados do gerente regional.'
                      : 'Cadastre um gerente regional com acesso ao painel.',
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
    );
  }

  Widget _campo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    bool enabled = true,
    Widget? trailing,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      enabled: enabled,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: trailing,
        filled: !enabled,
        fillColor: !enabled ? Colors.grey.shade100 : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:depertin_web/services/firebase_functions_config.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ——— Máscaras data (DD/MM/AAAA) e CPF ———

String _maskDataNascimentoFromDigits(String digits) {
  var d = digits.replaceAll(RegExp(r'\D'), '');
  if (d.length > 8) d = d.substring(0, 8);
  if (d.isEmpty) return '';
  if (d.length <= 2) return d;
  if (d.length <= 4) return '${d.substring(0, 2)}/${d.substring(2)}';
  return '${d.substring(0, 2)}/${d.substring(2, 4)}/${d.substring(4)}';
}

String _maskCpfFromDigits(String digits) {
  var d = digits.replaceAll(RegExp(r'\D'), '');
  if (d.length > 11) d = d.substring(0, 11);
  if (d.isEmpty) return '';
  if (d.length <= 3) return d;
  if (d.length <= 6) return '${d.substring(0, 3)}.${d.substring(3)}';
  if (d.length <= 9) {
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6)}';
  }
  return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
}

/// Insere barras enquanto o usuário digita (apenas dígitos, máx. 8).
class _DataNascimentoInputFormatter extends TextInputFormatter {
  const _DataNascimentoInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final masked = _maskDataNascimentoFromDigits(digits);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// Insere pontos e hífen enquanto o usuário digita (apenas dígitos, máx. 11).
class _CpfInputFormatter extends TextInputFormatter {
  const _CpfInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final masked = _maskCpfFromDigits(digits);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// Cadastro e gerenciamento de colaboradores do painel web (nível III).
class ColaboradoresLojistaPainelCard extends StatefulWidget {
  const ColaboradoresLojistaPainelCard({super.key, required this.uidLoja});

  final String uidLoja;

  @override
  State<ColaboradoresLojistaPainelCard> createState() =>
      _ColaboradoresLojistaPainelCardState();
}

class _ColaboradoresLojistaPainelCardState
    extends State<ColaboradoresLojistaPainelCard> {
  String _filtroBusca = '';

  @override
  Widget build(BuildContext context) {
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BarraAcoesEquipe(
          onNovo: () async {
            final ok = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => const _DialogoColaborador(
                modo: _ModoDialogColaborador.criar,
              ),
            );
            if (ok == true && context.mounted) {
              await _mostrarAnimacaoSucesso(context);
            }
          },
          onBusca: (v) => setState(() => _filtroBusca = v),
        ),
        const SizedBox(height: 24),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where('lojista_owner_uid', isEqualTo: widget.uidLoja)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return _ErroLista(mensagem: '${snap.error}');
            }
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator(
                    color: PainelAdminTheme.roxo,
                  ),
                ),
              );
            }
            var docs = snap.data?.docs ?? [];

            // Aplicar busca client-side
            if (_filtroBusca.isNotEmpty) {
              docs = docs.where((d) {
                final m = d.data();
                final nome = (m['nome'] ?? m['nome_completo'] ?? '').toString().toLowerCase();
                final email = (m['email'] ?? '').toString().toLowerCase();
                final cpf = (m['cpf'] ?? '').toString().toLowerCase();
                final b = _filtroBusca.toLowerCase();
                return nome.contains(b) || email.contains(b) || cpf.contains(b);
              }).toList();
            }

            if (docs.isEmpty) {
              return _filtroBusca.isEmpty
                  ? _EstadoVazio(
                      onAdicionar: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (ctx) => const _DialogoColaborador(
                            modo: _ModoDialogColaborador.criar,
                          ),
                        );
                        if (ok == true && context.mounted) {
                          await _mostrarAnimacaoSucesso(context);
                        }
                      },
                    )
                  : _EstadoBuscaVazia(onLimpar: () => setState(() => _filtroBusca = ''));
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final d = docs[index];
                return _CardColaborador(
                  doc: d,
                  authUid: authUid,
                  onEditar: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) => _DialogoColaborador(
                        modo: _ModoDialogColaborador.editar,
                        documento: d,
                      ),
                    );
                    if (ok == true && context.mounted) {
                      await _mostrarAnimacaoSucesso(context);
                    }
                  },
                  onEliminar: () => _confirmarEliminar(context, d.id, d.data()),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Future<void> _mostrarAnimacaoSucesso(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => const _OverlaySucessoCadastro(),
    );
  }

  Future<void> _confirmarEliminar(
    BuildContext context,
    String targetUid,
    Map<String, dynamic> dados,
  ) async {
    final nome = (dados['nome'] ?? dados['nome_completo'] ?? 'Usuário')
        .toString();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Remover colaborador',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Tem certeza que deseja remover o acesso de "$nome"? Esta ação não pode ser desfeita.',
          style: GoogleFonts.plusJakartaSans(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
              foregroundColor: Colors.white,
            ),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (c) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: PainelAdminTheme.roxo),
                SizedBox(height: 16),
                Text('Removendo…'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await callFirebaseFunctionSafe(
        'removerColaboradorPainelLojista',
        parameters: {'targetUid': targetUid},
      );
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Colaborador removido.',
            style: GoogleFonts.plusJakartaSans(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF15803D),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Não foi possível remover.'),
            backgroundColor: const Color(0xFFB91C1C),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on CallableHttpException catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: const Color(0xFFB91C1C),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: const Color(0xFFB91C1C),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ——— Barra de Ações ———

class _BarraAcoesEquipe extends StatelessWidget {
  const _BarraAcoesEquipe({required this.onNovo, required this.onBusca});

  final VoidCallback onNovo;
  final ValueChanged<String> onBusca;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: PainelAdminTheme.sombraCardSuave(),
            ),
            child: TextField(
              onChanged: onBusca,
              style: GoogleFonts.plusJakartaSans(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Buscar por nome, e-mail ou CPF...',
                hintStyle: GoogleFonts.plusJakartaSans(
                  color: PainelAdminTheme.textoSecundario.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        FilledButton.icon(
          onPressed: onNovo,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Novo colaborador'),
          style: FilledButton.styleFrom(
            backgroundColor: PainelAdminTheme.roxo,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
        ),
      ],
    );
  }
}

// ——— Cards ———

class _CardColaborador extends StatelessWidget {
  const _CardColaborador({
    required this.doc,
    required this.authUid,
    required this.onEditar,
    required this.onEliminar,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String authUid;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;

  static String _formatarCpf(String? raw) {
    final d = (raw ?? '').replaceAll(RegExp(r'\D'), '');
    if (d.length != 11) return (raw == null || raw.isEmpty) ? '—' : raw;
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
  }

  static String _textoNivelPainel(Map<String, dynamic> m) {
    final nv = m['painel_colaborador_nivel'];
    int? n;
    if (nv is num) n = nv.toInt();
    else if (nv is String) n = int.tryParse(nv);
    if (n == null) return 'Nível I';
    n = n.clamp(1, 3);
    if (n == 1) return 'Nível I';
    if (n == 2) return 'Nível II';
    return 'Nível III';
  }

  @override
  Widget build(BuildContext context) {
    final m = doc.data();
    final nome = (m['nome'] ?? m['nome_completo'] ?? '—').toString();
    final email = (m['email'] ?? '—').toString();
    final cpf = _formatarCpf(m['cpf']?.toString());
    final nivelTxt = _textoNivelPainel(m);
    final mesmoEu = doc.id == authUid;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: PainelAdminTheme.sombraCardSuave(),
        border: Border.all(color: Colors.white),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: PainelAdminTheme.roxo.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                nome.isNotEmpty ? nome[0].toUpperCase() : '?',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800,
                  color: PainelAdminTheme.roxo,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      nome,
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: PainelAdminTheme.dashboardInk,
                      ),
                    ),
                    if (mesmoEu) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: PainelAdminTheme.roxo.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'VOCÊ',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: PainelAdminTheme.roxo,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.email_outlined, size: 14, color: PainelAdminTheme.textoSecundario),
                    const SizedBox(width: 4),
                    Text(
                      email,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: PainelAdminTheme.textoSecundario,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.badge_outlined, size: 14, color: PainelAdminTheme.textoSecundario),
                    const SizedBox(width: 4),
                    Text(
                      cpf,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: PainelAdminTheme.textoSecundario,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: PainelAdminTheme.roxo.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: PainelAdminTheme.roxo.withValues(alpha: 0.1)),
            ),
            child: Text(
              nivelTxt,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: PainelAdminTheme.roxo,
              ),
            ),
          ),
          const SizedBox(width: 16),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade400),
            tooltip: 'Ações',
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'editar') onEditar();
              if (val == 'remover') onEliminar();
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'editar',
                enabled: !mesmoEu,
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18, color: mesmoEu ? Colors.grey : PainelAdminTheme.roxo),
                    const SizedBox(width: 12),
                    Text('Editar dados', style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'remover',
                enabled: !mesmoEu,
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFB91C1C)),
                    const SizedBox(width: 12),
                    Text('Remover acesso', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: const Color(0xFFB91C1C))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EstadoBuscaVazia extends StatelessWidget {
  const _EstadoBuscaVazia({required this.onLimpar});
  final VoidCallback onLimpar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Nenhum colaborador encontrado',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: PainelAdminTheme.dashboardInk,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tente ajustar os termos da sua busca.',
              style: GoogleFonts.plusJakartaSans(color: PainelAdminTheme.textoSecundario),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: onLimpar,
              child: const Text('Limpar busca'),
            ),
          ],
        ),
      ),
    );
  }
}

// ——— Estados lista ———

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio({required this.onAdicionar});

  final VoidCallback onAdicionar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: PainelAdminTheme.sombraCardSuave(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: PainelAdminTheme.roxo.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.people_outline_rounded,
              size: 40,
              color: PainelAdminTheme.roxo.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Sua equipe ainda está vazia',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: PainelAdminTheme.dashboardInk,
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Text(
              'Adicione colaboradores para ajudar na gestão da sua loja. Você pode definir diferentes níveis de acesso para cada um.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                color: PainelAdminTheme.textoSecundario,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: onAdicionar,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Adicionar primeiro colaborador'),
            style: FilledButton.styleFrom(
              backgroundColor: PainelAdminTheme.roxo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErroLista extends StatelessWidget {
  const _ErroLista({required this.mensagem});

  final String mensagem;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
          const SizedBox(width: 12),
          Expanded(child: Text(mensagem)),
        ],
      ),
    );
  }
}

// ——— Diálogo criar / editar ———

enum _ModoDialogColaborador { criar, editar }

class _DialogoColaborador extends StatefulWidget {
  const _DialogoColaborador({
    required this.modo,
    this.documento,
  });

  final _ModoDialogColaborador modo;
  final QueryDocumentSnapshot<Map<String, dynamic>>? documento;

  @override
  State<_DialogoColaborador> createState() => _DialogoColaboradorState();
}

class _DialogoColaboradorState extends State<_DialogoColaborador> {
  final _nome = TextEditingController();
  final _dataNasc = TextEditingController();
  final _cpf = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _senha2 = TextEditingController();

  int _nivel = 1;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    if (widget.modo == _ModoDialogColaborador.editar && widget.documento != null) {
      final m = widget.documento!.data();
      _nome.text = (m['nome'] ?? m['nome_completo'] ?? '').toString();
      final dnDigits =
          (m['data_nascimento'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      _dataNasc.text = _maskDataNascimentoFromDigits(dnDigits);
      final cpfRaw =
          (m['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      _cpf.text = _maskCpfFromDigits(cpfRaw);
      _email.text = (m['email'] ?? '').toString();
      final nv = m['painel_colaborador_nivel'];
      if (nv is num) {
        _nivel = nv.toInt().clamp(1, 3);
      } else if (nv is String) {
        final v = int.tryParse(nv.trim());
        if (v != null) _nivel = v.clamp(1, 3);
      }
    }
  }

  @override
  void dispose() {
    _nome.dispose();
    _dataNasc.dispose();
    _cpf.dispose();
    _email.dispose();
    _senha.dispose();
    _senha2.dispose();
    super.dispose();
  }

  static String _soDigitos(String s) => s.replaceAll(RegExp(r'\D'), '');

  Future<void> _salvar() async {
    final nome = _nome.text.trim();
    if (nome.length < 3) {
      _snack('Informe o nome completo.', erro: true);
      return;
    }
    final dnDigitos = _soDigitos(_dataNasc.text);
    if (dnDigitos.isEmpty) {
      _snack('Informe a data de nascimento.', erro: true);
      return;
    }
    if (dnDigitos.length != 8) {
      _snack('Data de nascimento: informe o dia, mês e ano (DD/MM/AAAA).', erro: true);
      return;
    }
    final dn = _dataNasc.text.trim();
    final cpf = _soDigitos(_cpf.text);
    if (cpf.length != 11) {
      _snack('CPF deve ter 11 dígitos.', erro: true);
      return;
    }
    final email = _email.text.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _snack('E-mail inválido.', erro: true);
      return;
    }

    final s1 = _senha.text;
    final s2 = _senha2.text;
    if (widget.modo == _ModoDialogColaborador.criar) {
      if (s1.length < 6) {
        _snack('A senha deve ter pelo menos 6 caracteres.', erro: true);
        return;
      }
      if (s1 != s2) {
        _snack('As senhas não coincidem.', erro: true);
        return;
      }
    } else {
      if (s1.isNotEmpty || s2.isNotEmpty) {
        if (s1.length < 6) {
          _snack('A nova senha deve ter pelo menos 6 caracteres.', erro: true);
          return;
        }
        if (s1 != s2) {
          _snack('As senhas não coincidem.', erro: true);
          return;
        }
      }
    }

    setState(() => _enviando = true);
    try {
      if (widget.modo == _ModoDialogColaborador.criar) {
        await callFirebaseFunctionSafe(
          'cadastrarColaboradorPainelLojista',
          parameters: {
            'email': email,
            'password': s1,
            'nomeCompleto': nome,
            'dataNascimento': dn,
            'cpf': cpf,
            'nivel': _nivel,
          },
        );
      } else {
        final payload = <String, dynamic>{
          'targetUid': widget.documento!.id,
          'nomeCompleto': nome,
          'dataNascimento': dn,
          'cpf': cpf,
          'nivel': _nivel,
          'email': email,
        };
        if (s1.isNotEmpty) {
          payload['password'] = s1;
        }
        await callFirebaseFunctionSafe(
          'atualizarColaboradorPainelLojista',
          parameters: payload,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? 'Operação não concluída.', erro: true);
    } on CallableHttpException catch (e) {
      _snack(e.message, erro: true);
    } catch (e) {
      _snack('$e', erro: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: erro ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.plusJakartaSans(
        color: PainelAdminTheme.textoSecundario,
        fontSize: 14,
      ),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      prefixIcon: Container(
        margin: const EdgeInsets.only(right: 12, left: 12),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: PainelAdminTheme.roxo.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: PainelAdminTheme.roxo),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: PainelAdminTheme.roxo, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editar = widget.modo == _ModoDialogColaborador.editar;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: PainelAdminTheme.roxo.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      editar ? Icons.edit_outlined : Icons.person_add_alt_1_rounded,
                      color: PainelAdminTheme.roxo,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      editar ? 'Alterar colaborador' : 'Novo colaborador',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: PainelAdminTheme.dashboardInk,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _enviando ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(foregroundColor: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                editar
                    ? 'Atualize os dados abaixo. Deixe as senhas em branco para mantê-las.'
                    : 'Preencha os campos a baixo.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  color: PainelAdminTheme.textoSecundario,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.58,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: _nome,
                        textCapitalization: TextCapitalization.words,
                        decoration: _dec('Nome completo', Icons.badge_outlined),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _dataNasc,
                        keyboardType: TextInputType.number,
                        inputFormatters: const [_DataNascimentoInputFormatter()],
                        decoration: _dec(
                          'Data de nascimento',
                          Icons.cake_outlined,
                        ).copyWith(
                          hintText: 'DD/MM/AAAA',
                          hintStyle: TextStyle(
                            color: PainelAdminTheme.textoSecundario
                                .withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _cpf,
                        keyboardType: TextInputType.number,
                        inputFormatters: const [_CpfInputFormatter()],
                        decoration: _dec('CPF', Icons.badge_outlined).copyWith(
                          hintText: '000.000.000-00',
                          hintStyle: TextStyle(
                            color: PainelAdminTheme.textoSecundario
                                .withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: _dec('E-mail (login)', Icons.email_outlined),
                      ),
                      const SizedBox(height: 12),
                      if (!editar) ...[
                        TextField(
                          controller: _senha,
                          obscureText: true,
                          decoration: _dec('Senha', Icons.lock_outline),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _senha2,
                          obscureText: true,
                          decoration: _dec('Confirmar senha', Icons.lock_outline),
                        ),
                      ] else ...[
                        TextField(
                          controller: _senha,
                          obscureText: true,
                          decoration: _dec(
                            'Nova senha (opcional)',
                            Icons.lock_outline,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _senha2,
                          obscureText: true,
                          decoration: _dec(
                            'Confirmar nova senha',
                            Icons.lock_outline,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        // value controlado por setState; initialValue não serve aqui.
                        // ignore: deprecated_member_use
                        value: _nivel,
                        decoration: _dec('Nível de acesso', Icons.layers_outlined),
                        items: const [
                          DropdownMenuItem(
                            value: 1,
                            child: Text('Nível I — Dashboard e Meus pedidos'),
                          ),
                          DropdownMenuItem(
                            value: 2,
                            child: Text(
                              'Nível II — + Meus produtos e Gestão Comercial',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 3,
                            child: Text(
                              'Nível III — Carteira, configurações, equipe e Gestão Comercial',
                            ),
                          ),
                        ],
                        onChanged: _enviando
                            ? null
                            : (v) {
                                if (v != null) setState(() => _nivel = v);
                              },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _enviando ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    ),
                    child: Text(
                      'Cancelar',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        color: PainelAdminTheme.textoSecundario,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _enviando ? null : _salvar,
                    style: FilledButton.styleFrom(
                      backgroundColor: PainelAdminTheme.roxo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 18,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _enviando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            editar ? 'Salvar alterações' : 'Confirmar e criar',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
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

// ——— Animação sucesso ———

class _OverlaySucessoCadastro extends StatefulWidget {
  const _OverlaySucessoCadastro();

  @override
  State<_OverlaySucessoCadastro> createState() => _OverlaySucessoCadastroState();
}

class _OverlaySucessoCadastroState extends State<_OverlaySucessoCadastro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _escala;
  late final Animation<double> _opacidade;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _escala = CurvedAnimation(parent: _c, curve: Curves.elasticOut);
    _opacidade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _c, curve: const Interval(0, 0.45, curve: Curves.easeOut)),
    );
    _c.forward();
    Future<void>.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: FadeTransition(
          opacity: _opacidade,
          child: ScaleTransition(
            scale: _escala,
            child: Container(
              width: 300,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF22C55E), Color(0xFF15803D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Cadastro concluído',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: PainelAdminTheme.dashboardInk,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Os dados foram salvos com sucesso.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: PainelAdminTheme.textoSecundario,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

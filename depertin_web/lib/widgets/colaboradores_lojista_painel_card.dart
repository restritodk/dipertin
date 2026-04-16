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
  @override
  Widget build(BuildContext context) {
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Container(
      decoration: PainelAdminTheme.dashboardCard(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CabecalhoEquipe(
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
          ),
          const Divider(height: 1, thickness: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(
                        color: PainelAdminTheme.roxo,
                      ),
                    ),
                  );
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return _EstadoVazio(
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
                  );
                }
                return _TabelaColaboradores(
                  docs: docs,
                  authUid: authUid,
                  onEditar: (doc) async {
                    final ok = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) => _DialogoColaborador(
                        modo: _ModoDialogColaborador.editar,
                        documento: doc,
                      ),
                    );
                    if (ok == true && context.mounted) {
                      await _mostrarAnimacaoSucesso(context);
                    }
                  },
                  onEliminar: (doc) =>
                      _confirmarEliminar(context, doc.id, doc.data()),
                );
              },
            ),
          ),
        ],
      ),
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

// ——— Cabeçalho ———

class _CabecalhoEquipe extends StatelessWidget {
  const _CabecalhoEquipe({required this.onNovo});

  final VoidCallback onNovo;

  @override
  Widget build(BuildContext context) {
    final botao = FilledButton.icon(
      onPressed: onNovo,
      icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
      label: Text(
        'Novo colaborador',
        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: PainelAdminTheme.roxo,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );

    final icone = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            PainelAdminTheme.roxo.withValues(alpha: 0.14),
            PainelAdminTheme.roxo.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: PainelAdminTheme.roxo.withValues(alpha: 0.2),
        ),
      ),
      child: Icon(
        Icons.groups_2_outlined,
        color: PainelAdminTheme.roxo,
        size: 26,
      ),
    );

    final blocoTexto = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'CADASTRE SUA EQUIPE DE COLABORADORES',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: PainelAdminTheme.dashboardInk,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Gerencie sua equipe de colaboradores para compartilhar o acesso ao painel.',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13.5,
            color: PainelAdminTheme.textoSecundario,
            height: 1.5,
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          icone,
          const SizedBox(height: 16),
          blocoTexto,
          const SizedBox(height: 20),
          botao,
        ],
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
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PainelAdminTheme.dashboardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline_rounded,
            size: 48,
            color: PainelAdminTheme.textoSecundario.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'Ainda não há colaboradores',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: PainelAdminTheme.dashboardInk,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Adicione o primeiro membro da equipe para compartilhar o acesso ao painel.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: PainelAdminTheme.textoSecundario,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onAdicionar,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Adicionar colaborador'),
            style: OutlinedButton.styleFrom(
              foregroundColor: PainelAdminTheme.roxo,
              side: BorderSide(color: PainelAdminTheme.roxo.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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

// ——— Tabela ———

class _TabelaColaboradores extends StatelessWidget {
  const _TabelaColaboradores({
    required this.docs,
    required this.authUid,
    required this.onEditar,
    required this.onEliminar,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String authUid;
  final void Function(QueryDocumentSnapshot<Map<String, dynamic>>) onEditar;
  final void Function(QueryDocumentSnapshot<Map<String, dynamic>>) onEliminar;

  static String _formatarCpf(String? raw) {
    final d = (raw ?? '').replaceAll(RegExp(r'\D'), '');
    if (d.length != 11) {
      return (raw == null || raw.isEmpty) ? '—' : raw;
    }
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
  }

  /// Texto curto para a coluna (alinha com o formulário de cadastro).
  static String _textoNivelPainel(Map<String, dynamic> m) {
    final nv = m['painel_colaborador_nivel'];
    int? n;
    if (nv is int) {
      n = nv;
    } else if (nv is num) {
      n = nv.toInt();
    } else if (nv is String) {
      n = int.tryParse(nv.trim());
    }
    if (n == null) return '—';
    n = n.clamp(1, 3);
    switch (n) {
      case 1:
        return 'Nível I';
      case 2:
        return 'Nível II';
      case 3:
        return 'Nível III';
      default:
        return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final table = Table(
          columnWidths: const {
            0: FlexColumnWidth(2.0),
            1: FlexColumnWidth(1.35),
            2: FlexColumnWidth(2.1),
            3: FlexColumnWidth(1.15),
            4: FixedColumnWidth(108),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              children: [
                _th('Nome'),
                _th('CPF'),
                _th('E-mail'),
                _th('Nível'),
                _th('Ação'),
              ],
            ),
            ...docs.map((d) {
              final m = d.data();
              final nome =
                  (m['nome'] ?? m['nome_completo'] ?? '—').toString();
              final cpf = _formatarCpf(m['cpf']?.toString());
              final email = (m['email'] ?? '—').toString();
              final nivelTxt = _textoNivelPainel(m);
              final mesmoEu = d.id == authUid;
              return TableRow(
                key: ValueKey(d.id),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: PainelAdminTheme.dashboardBorder.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
                ),
                children: [
                  _td(
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            nome,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: PainelAdminTheme.dashboardInk,
                            ),
                          ),
                        ),
                        if (mesmoEu)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: PainelAdminTheme.roxo.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Você',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: PainelAdminTheme.roxo,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _td(
                    Text(
                      cpf,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        color: const Color(0xFF475569),
                        letterSpacing: 0.2,
                      ),
                    ),
                    center: true,
                  ),
                  _td(
                    Tooltip(
                      message: email,
                      child: Text(
                        email,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          color: const Color(0xFF475569),
                        ),
                      ),
                    ),
                    center: true,
                  ),
                  _td(
                    nivelTxt == '—'
                        ? Text(
                            '—',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13.5,
                              color: PainelAdminTheme.textoSecundario,
                            ),
                          )
                        : Tooltip(
                            message:
                                'Permissões no painel: $nivelTxt',
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: PainelAdminTheme.roxo.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: PainelAdminTheme.roxo.withValues(
                                      alpha: 0.22,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  nivelTxt,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: PainelAdminTheme.roxo,
                                  ),
                                ),
                              ),
                            ),
                          ),
                    center: true,
                  ),
                  _td(
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Alterar dados',
                          onPressed: mesmoEu ? null : () => onEditar(d),
                          icon: Icon(
                            Icons.edit_outlined,
                            size: 20,
                            color: mesmoEu
                                ? Colors.grey.shade400
                                : PainelAdminTheme.roxo,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remover',
                          onPressed: mesmoEu ? null : () => onEliminar(d),
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: mesmoEu
                                ? Colors.grey.shade400
                                : const Color(0xFFB91C1C),
                          ),
                        ),
                      ],
                    ),
                    center: true,
                  ),
                ],
              );
            }),
          ],
        );

        if (constraints.maxWidth < 720) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: constraints.maxWidth > 680 ? constraints.maxWidth : 680,
              ),
              child: table,
            ),
          );
        }
        return table;
      },
    );
  }

  static Widget _th(String t, {bool center = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(
        t.toUpperCase(),
        textAlign: center ? TextAlign.center : TextAlign.start,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
          color: PainelAdminTheme.textoSecundario,
        ),
      ),
    );
  }

  static Widget _td(Widget child, {bool center = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: center
          ? Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: double.infinity,
                child: child,
              ),
            )
          : child,
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
      prefixIcon: Icon(icon, size: 20, color: PainelAdminTheme.textoSecundario),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
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
                            child: Text('Nível II — + Meus produtos'),
                          ),
                          DropdownMenuItem(
                            value: 3,
                            child: Text(
                              'Nível III — Carteira, configurações e equipe',
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
                      backgroundColor: PainelAdminTheme.laranja,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _enviando
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            editar ? 'Salvar alterações' : 'Cadastrar',
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

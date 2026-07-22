import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/audit_log_model.dart';
import '../../services/auditoria_service.dart';
import '../../theme/painel_admin_theme.dart';

/// Campo de busca com debounce (300ms) e autocomplete de usuários.
class AuditoriaUsuarioSearch extends StatefulWidget {
  const AuditoriaUsuarioSearch({
    super.key,
    required this.categoriaAtor,
    required this.onSelecionar,
    this.usuarioSelecionado,
    this.onLimpar,
  });

  final String? categoriaAtor;
  final String? usuarioSelecionado;
  final void Function(AuditUser? user) onSelecionar;
  final VoidCallback? onLimpar;

  @override
  State<AuditoriaUsuarioSearch> createState() => _AuditoriaUsuarioSearchState();
}

class _AuditoriaUsuarioSearchState extends State<AuditoriaUsuarioSearch> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<AuditUser> _sugestoes = const [];
  bool _carregando = false;
  bool _aberto = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    if (widget.usuarioSelecionado != null) {
      _ctrl.text = widget.usuarioSelecionado!;
    }
  }

  @override
  void didUpdateWidget(covariant AuditoriaUsuarioSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.usuarioSelecionado != oldWidget.usuarioSelecionado &&
        widget.usuarioSelecionado != null) {
      _ctrl.text = widget.usuarioSelecionado!;
    } else if (widget.usuarioSelecionado == null && oldWidget.usuarioSelecionado != null) {
      _ctrl.clear();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _sugestoes = const [];
        _aberto = false;
        _erro = null;
      });
      widget.onSelecionar(null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _pesquisar(v);
    });
  }

  Future<void> _pesquisar(String v) async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final res = await AuditoriaService.pesquisarUsuarios(
        termo: v.trim(),
        categoria: widget.categoriaAtor,
        limite: 12,
      );
      if (!mounted) return;
      setState(() {
        _sugestoes = res;
        _aberto = true;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Falha ao buscar';
        _sugestoes = const [];
      });
    }
  }

  void _limpar() {
    _ctrl.clear();
    _debounce?.cancel();
    setState(() {
      _sugestoes = const [];
      _aberto = false;
      _erro = null;
    });
    widget.onLimpar?.call();
    widget.onSelecionar(null);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: PainelAdminTheme.dashboardBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, size: 20,
                  color: PainelAdminTheme.textoSecundario),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  onChanged: _onChanged,
                  onTap: () {
                    if (_sugestoes.isNotEmpty) {
                      setState(() => _aberto = true);
                    }
                  },
                  decoration: const InputDecoration(
                    hintText: 'Buscar por nome, CPF, CNPJ, e-mail, telefone ou UID…',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (_carregando)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (_ctrl.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Limpar busca',
                  onPressed: _limpar,
                ),
            ],
          ),
        ),
        if (_aberto)
          Container(
            margin: const EdgeInsets.only(top: 8),
            constraints: const BoxConstraints(maxHeight: 360),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PainelAdminTheme.dashboardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: _erro != null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_erro!,
                        style: const TextStyle(
                            color: PainelAdminTheme.errorRedAlt,
                            fontSize: 13)),
                  )
                : _sugestoes.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Nenhum usuário encontrado para os filtros aplicados.',
                          style: TextStyle(
                              fontSize: 13,
                              color: PainelAdminTheme.textoSecundario),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _sugestoes.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final u = _sugestoes[i];
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor:
                                  PainelAdminTheme.roxo.withValues(alpha: 0.12),
                              child: Text(
                                (u.nome ?? '?').isNotEmpty
                                    ? (u.nome ?? '?')[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: PainelAdminTheme.roxo,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            title: Text(
                              u.nome ?? '(sem nome)',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            subtitle: Text(
                              [
                                if ((u.documentoMascarado ?? '').isNotEmpty)
                                  u.documentoMascarado!,
                                if ((u.emailMascarado ?? '').isNotEmpty)
                                  u.emailMascarado!,
                                if ((u.role ?? '').isNotEmpty) u.role!,
                                if ((u.cidade ?? '').isNotEmpty) u.cidade!,
                              ].join(' · '),
                              style: const TextStyle(fontSize: 12),
                            ),
                            onTap: () {
                              setState(() {
                                _aberto = false;
                                _ctrl.text = u.nome ?? u.uid;
                              });
                              widget.onSelecionar(u);
                            },
                          );
                        },
                      ),
          ),
      ],
    );
  }
}

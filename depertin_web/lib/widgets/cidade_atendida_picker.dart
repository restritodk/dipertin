import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Item exibido no seletor de cidade atendida.
class CidadePickerItem {
  final String label;
  final String nome;
  final String uf;
  final String nomeNorm;
  final String ufNorm;

  const CidadePickerItem({
    required this.label,
    required this.nome,
    required this.uf,
    required this.nomeNorm,
    required this.ufNorm,
  });
}

/// Campo profissional para selecionar uma cidade a partir de uma lista grande.
///
/// Apresenta-se como um campo (estilo dropdown) e, ao tocar, abre um diálogo
/// com barra de busca (ícone de lupa) e lista virtualizada das cidades.
///
/// Ideal para quando há milhares de opções (ex.: 5.570 municípios do IBGE).
class CidadeAtendidaPicker extends StatelessWidget {
  final CidadePickerItem? selecionada;
  final List<CidadePickerItem> todas;
  final ValueChanged<CidadePickerItem> onSelecionada;
  final String label;
  final String placeholder;

  /// Texto opcional exibido no cabeçalho do diálogo (ex.: "5.570 cidades disponíveis").
  /// Se null, usa "${todas.length} cidades ativas disponíveis".
  final String? descricaoDialog;

  /// Título opcional do diálogo de seleção.
  final String tituloDialog;

  /// Quando `true`, adiciona um botão "Limpar seleção" no diálogo, útil quando
  /// a ausência de cidade tem semântica válida (ex.: anúncio em todo o Brasil).
  final bool permitirLimpar;

  /// Callback chamado quando o usuário toca em "Limpar seleção".
  final VoidCallback? onLimpar;

  /// Mensagem opcional exibida abaixo do campo quando nenhuma cidade está
  /// selecionada (ex.: "Em branco = anúncio em todo o Brasil").
  final String? helperQuandoVazio;

  const CidadeAtendidaPicker({
    super.key,
    required this.selecionada,
    required this.todas,
    required this.onSelecionada,
    this.label = 'Cidade atendida',
    this.placeholder = 'Selecione uma cidade',
    this.descricaoDialog,
    this.tituloDialog = 'Selecionar cidade atendida',
    this.permitirLimpar = false,
    this.onLimpar,
    this.helperQuandoVazio,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: todas.isEmpty
              ? null
              : () async {
                  final sel = await _abrirSeletor(context);
                  if (sel == null) return;
                  if (sel.nomeNorm.isEmpty && sel.ufNorm.isEmpty) {
                    onLimpar?.call();
                  } else {
                    onSelecionada(sel);
                  }
                },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              hintText: placeholder,
              prefixIcon: const Icon(Icons.location_city_outlined),
              suffixIcon: selecionada != null && permitirLimpar
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: 'Limpar seleção',
                      onPressed: onLimpar,
                    )
                  : const Icon(Icons.arrow_drop_down_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            isEmpty: selecionada == null,
            child: selecionada == null
                ? null
                : Text(
                    selecionada!.label,
                    style: const TextStyle(color: Colors.black87),
                  ),
          ),
        ),
        if (selecionada == null &&
            helperQuandoVazio != null &&
            helperQuandoVazio!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              helperQuandoVazio!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<CidadePickerItem?> _abrirSeletor(BuildContext context) {
    return showDialog<CidadePickerItem>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _SeletorCidadeDialog(
        todas: todas,
        selecionadaAtual: selecionada,
        descricao: descricaoDialog,
        titulo: tituloDialog,
        permitirLimpar: permitirLimpar,
      ),
    );
  }
}

class _SeletorCidadeDialog extends StatefulWidget {
  final List<CidadePickerItem> todas;
  final CidadePickerItem? selecionadaAtual;
  final String? descricao;
  final String titulo;
  final bool permitirLimpar;

  const _SeletorCidadeDialog({
    required this.todas,
    required this.selecionadaAtual,
    required this.titulo,
    this.descricao,
    this.permitirLimpar = false,
  });

  @override
  State<_SeletorCidadeDialog> createState() => _SeletorCidadeDialogState();
}

class _SeletorCidadeDialogState extends State<_SeletorCidadeDialog> {
  static const Color _roxo = Color(0xFF6A1B9A);
  static const Color _laranja = Color(0xFFFF8F00);

  late List<CidadePickerItem> _filtradas;
  String _query = '';
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _filtradas = widget.todas;
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  String _normalizar(String s) {
    var t = s.toLowerCase();
    const from = 'àáâãäåèéêëìíîïòóôõöùúûüçñ';
    const to = 'aaaaaaeeeeiiiiooooouuuucn';
    for (var i = 0; i < from.length; i++) {
      t = t.replaceAll(from[i], to[i]);
    }
    return t;
  }

  void _aplicarFiltro(String v) {
    final q = _normalizar(v.trim());
    setState(() {
      _query = v;
      if (q.isEmpty) {
        _filtradas = widget.todas;
      } else {
        _filtradas = widget.todas.where((c) {
          final alvo = _normalizar('${c.nome} ${c.uf} ${c.label}');
          return alvo.contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 620),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            _buildSearch(),
            const Divider(height: 1),
            Flexible(child: _buildLista()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_roxo, Color(0xFF8E24AA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.location_city_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
            Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  widget.descricao ??
                      '${widget.todas.length} cidades ativas disponíveis',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.82),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Fechar',
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: TextField(
        focusNode: _focus,
        autofocus: true,
        onChanged: _aplicarFiltro,
        decoration: InputDecoration(
          hintText: 'Buscar por cidade ou UF…',
          hintStyle: GoogleFonts.plusJakartaSans(color: Colors.grey.shade500),
          prefixIcon: const Icon(Icons.search_rounded, color: _roxo),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () {
                    _aplicarFiltro('');
                    _focus.requestFocus();
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFFF7F4FA),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _roxo.withOpacity(0.4)),
          ),
        ),
      ),
    );
  }

  Widget _buildLista() {
    if (_filtradas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, color: Colors.grey.shade400, size: 44),
            const SizedBox(height: 10),
            Text(
              'Nenhuma cidade encontrada',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tente outro termo ou verifique se a cidade está ativa na aba "Cadastro de Cidades".',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      itemCount: _filtradas.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (ctx, i) {
        final c = _filtradas[i];
        final selecionado = widget.selecionadaAtual?.nomeNorm == c.nomeNorm &&
            widget.selecionadaAtual?.ufNorm == c.ufNorm;
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.pop(context, c),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: selecionado ? _roxo.withOpacity(0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selecionado
                    ? _roxo.withOpacity(0.35)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  color: selecionado ? _roxo : Colors.grey.shade500,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    c.nome,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight:
                          selecionado ? FontWeight.w700 : FontWeight.w500,
                      color: selecionado ? _roxo : Colors.grey.shade900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _laranja.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    c.uf,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: _laranja,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                if (selecionado) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle_rounded,
                      color: _roxo, size: 18),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline_rounded,
              size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${_filtradas.length} de ${widget.todas.length} cidades',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          if (widget.permitirLimpar)
            TextButton.icon(
              onPressed: () {
                // Retorna um item "vazio" que sinaliza limpeza ao chamador.
                Navigator.pop(
                  context,
                  const CidadePickerItem(
                    label: '',
                    nome: '',
                    uf: '',
                    nomeNorm: '',
                    ufNorm: '',
                  ),
                );
              },
              icon: Icon(Icons.public_rounded, size: 16, color: _laranja),
              label: Text(
                'Todo o Brasil',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  color: _laranja,
                ),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancelar',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/cidades_brasil_service.dart';

/// Modal premium para localizar e inserir o código IBGE de um município brasileiro.
class IbgeMunicipioPickerModal {
  IbgeMunicipioPickerModal._();

  static Future<CidadeSugestao?> abrir(BuildContext context) {
    return showDialog<CidadeSugestao>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => const _IbgeMunicipioPickerDialog(),
    );
  }
}

class _IbgeMunicipioPickerDialog extends StatefulWidget {
  const _IbgeMunicipioPickerDialog();

  @override
  State<_IbgeMunicipioPickerDialog> createState() =>
      _IbgeMunicipioPickerDialogState();
}

class _IbgeMunicipioPickerDialogState extends State<_IbgeMunicipioPickerDialog> {
  static const Color _roxo = Color(0xFF6A1B9A);
  static const Color _roxoClaro = Color(0xFF8E24AA);
  static const Color _laranja = Color(0xFFFF8F00);

  List<CidadeSugestao> _todas = [];
  List<CidadeSugestao> _filtradas = [];
  bool _carregando = true;
  String _query = '';
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _carregarMunicipios();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _carregarMunicipios() async {
    try {
      await CidadesBrasilService.precarregar();
      final lista = await CidadesBrasilService.todasCidades();
      if (!mounted) return;
      setState(() {
        _todas = lista;
        _filtradas = lista;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
      });
    }
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
        _filtradas = _todas;
        return;
      }
      _filtradas = _todas.where((c) {
        final alvo = _normalizar(
          '${c.nome} ${c.ufSigla} ${c.codigoIbge}',
        );
        return alvo.contains(q);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 640),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _roxo.withValues(alpha: 0.15),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 60,
              offset: const Offset(0, 20),
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
          colors: [_roxo, _roxoClaro],
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
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.map_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Código IBGE do Município',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _carregando
                      ? 'Carregando municípios…'
                      : '${_todas.length} municípios disponíveis',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.82),
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
          hintText: 'Buscar por município, UF ou código IBGE…',
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
            borderSide: BorderSide(color: _roxo.withValues(alpha: 0.4)),
          ),
        ),
      ),
    );
  }

  Widget _buildLista() {
    if (_carregando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: CircularProgressIndicator(color: _roxo),
        ),
      );
    }
    if (_filtradas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, color: Colors.grey.shade400, size: 44),
            const SizedBox(height: 10),
            Text(
              'Nenhum município encontrado',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tente outro termo de busca ou o código IBGE.',
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
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEEEAF6)),
          ),
          child: Row(
            children: [
              Icon(Icons.location_city_outlined,
                  color: Colors.grey.shade500, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.nome,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'IBGE: ${c.codigoIbge}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _laranja.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  c.ufSigla,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: _laranja,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.pop(context, c),
                  borderRadius: BorderRadius.circular(8),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_roxo, _roxoClaro],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      'Inserir',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
          Icon(Icons.info_outline_rounded,
              size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _carregando
                  ? 'Aguarde o carregamento…'
                  : '${_filtradas.length} de ${_todas.length} municípios',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

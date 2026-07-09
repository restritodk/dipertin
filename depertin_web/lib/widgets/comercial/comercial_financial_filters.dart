import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Barra de filtros premium para a tela de pendências financeiras.
class FinancialFilters extends StatelessWidget {
  const FinancialFilters({
    super.key,
    required this.buscaController,
    this.filtroStatus = 'Todos',
    this.filtroPlano = 'Todos',
    this.filtroVencimento = 'Todos',
    this.onBuscaChanged,
    this.onStatusChanged,
    this.onPlanoChanged,
    this.onVencimentoChanged,
    this.onPeriodoChanged,
    this.onLimpar,
  });

  final TextEditingController buscaController;
  final String filtroStatus;
  final String filtroPlano;
  final String filtroVencimento;
  final ValueChanged<String>? onBuscaChanged;
  final ValueChanged<String?>? onStatusChanged;
  final ValueChanged<String?>? onPlanoChanged;
  final ValueChanged<String?>? onVencimentoChanged;
  final VoidCallback? onPeriodoChanged;
  final VoidCallback? onLimpar;

  static const _statusOpcoes = [
    'Todos',
    'Vencido',
    'Vence hoje',
    'Vence em breve',
    'Em dia',
  ];

  static const _planoOpcoes = ['Todos', 'Avulso', 'Mensal', 'Semanal'];

  static const _vencimentoOpcoes = [
    'Todos',
    'Vencidos',
    'Vence hoje',
    'Próximos 7 dias',
    'Próximos 30 dias',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEAF6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Campo de busca
          SizedBox(
            height: 42,
            child: TextField(
              controller: buscaController,
              onChanged: onBuscaChanged,
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar por cliente, plano ou cobrança...',
                hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: const Color(0xFF94A3B8),
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: Color(0xFF94A3B8),
                ),
                suffixIcon: buscaController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          buscaController.clear();
                          onBuscaChanged?.call('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF8F9FC),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF6A1B9A),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Linha de filtros
          Row(
            children: [
              _filtroDropdown(
                'Status',
                filtroStatus,
                _statusOpcoes,
                onStatusChanged,
              ),
              const SizedBox(width: 8),
              _filtroDropdown(
                'Plano',
                filtroPlano,
                _planoOpcoes,
                onPlanoChanged,
              ),
              const SizedBox(width: 8),
              _filtroDropdown(
                'Vencimento',
                filtroVencimento,
                _vencimentoOpcoes,
                onVencimentoChanged,
              ),
              const SizedBox(width: 8),
              // Período - date range
              _filtroBotaoPeriodo(onPeriodoChanged),
              const SizedBox(width: 8),
              // Limpar
              if (_temFiltroAtivo)
                TextButton.icon(
                  onPressed: onLimpar,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF64748B),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: Text(
                    'Limpar filtros',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  bool get _temFiltroAtivo =>
      filtroStatus != 'Todos' ||
      filtroPlano != 'Todos' ||
      filtroVencimento != 'Todos';

  Widget _filtroDropdown(
    String label,
    String value,
    List<String> opcoes,
    ValueChanged<String?>? onChanged,
  ) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          icon: const Icon(Icons.expand_more_rounded, size: 16),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF1A1A2E),
          ),
          items: opcoes.map((o) {
            return DropdownMenuItem(
              value: o,
              child: Text(
                o == 'Todos' ? label : o,
                style: GoogleFonts.plusJakartaSans(fontSize: 12),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _filtroBotaoPeriodo(VoidCallback? onPressed) {
    return SizedBox(
      height: 38,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF1A1A2E),
          backgroundColor: const Color(0xFFF8F9FC),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
        icon: const Icon(Icons.date_range_rounded, size: 16),
        label: Text(
          'Período',
          style: GoogleFonts.plusJakartaSans(fontSize: 12),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../theme/painel_admin_theme.dart';

/// Data civil local (meia-noite) — evita deslocamento de dia por fuso ao salvar cupons.
DateTime dataSomenteLocal(DateTime d) => DateTime(d.year, d.month, d.day);

/// Calendário premium DiPertin (dialog) — painel web lojista/admin.
Future<DateTime?> showDiPertinDatePicker(
  BuildContext context, {
  required String titulo,
  String? subtitulo,
  DateTime? dataInicial,
  DateTime? dataMinima,
  DateTime? dataMaxima,
  bool mostrarAtalhosRapidos = true,
}) async {
  final agora = DateTime.now();
  final min = dataMinima ?? DateTime(agora.year - 1, agora.month, agora.day);
  final max = dataMaxima ?? DateTime(agora.year + 3, agora.month, agora.day);
  var selecionada = dataInicial ?? agora;
  if (selecionada.isBefore(min)) selecionada = min;
  if (selecionada.isAfter(max)) selecionada = max;

  return showDialog<DateTime>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.48),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final fmtLongo = DateFormat('EEEE, d \'de\' MMMM \'de\' y', 'pt_BR');
          final fmtCurto = DateFormat('dd/MM/yyyy', 'pt_BR');

          void definir(DateTime d) {
            var nd = DateTime(d.year, d.month, d.day);
            if (nd.isBefore(min)) nd = min;
            if (nd.isAfter(max)) nd = max;
            setLocal(() => selecionada = nd);
          }

          Widget chipAtalho(String rotulo, DateTime alvo) {
            final ativo = selecionada.year == alvo.year &&
                selecionada.month == alvo.month &&
                selecionada.day == alvo.day;
            return ActionChip(
              label: Text(rotulo),
              avatar: Icon(
                Icons.bolt_rounded,
                size: 16,
                color: ativo ? Colors.white : PainelAdminTheme.laranja,
              ),
              backgroundColor: ativo ? PainelAdminTheme.roxo : Colors.white,
              labelStyle: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: ativo ? Colors.white : PainelAdminTheme.dashboardInk,
              ),
              side: BorderSide(
                color: ativo ? PainelAdminTheme.roxo : Colors.grey.shade300,
              ),
              onPressed: () => definir(alvo),
            );
          }

          final hoje = DateTime(agora.year, agora.month, agora.day);
          final em7 = hoje.add(const Duration(days: 7));
          final em30 = hoje.add(const Duration(days: 30));
          final faixaAnosAmpla = max.year - min.year > 2;

          int diasNoMes(int ano, int mes) => DateTime(ano, mes + 1, 0).day;

          void definirAnoMes(int ano, int mes) {
            var dia = selecionada.day;
            final maxDia = diasNoMes(ano, mes);
            if (dia > maxDia) dia = maxDia;
            definir(DateTime(ano, mes, dia));
          }

          final anos = List.generate(
            max.year - min.year + 1,
            (i) => min.year + i,
          );
          const meses = [
            'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
            'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez',
          ];

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: PainelAdminTheme.roxo.withValues(alpha: 0.2),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            PainelAdminTheme.roxo.withValues(alpha: 0.95),
                            const Color(0xFF8E24AA),
                          ],
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.calendar_month_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  titulo,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (subtitulo != null && subtitulo.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitulo,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Text(
                                  fmtLongo.format(selecionada),
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  fmtCurto.format(selecionada),
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (mostrarAtalhosRapidos)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                chipAtalho('Hoje', hoje),
                                if (!em7.isAfter(max)) chipAtalho('Em 7 dias', em7),
                                if (!em30.isAfter(max)) chipAtalho('Em 30 dias', em30),
                              ],
                            ),
                          if (faixaAnosAmpla) ...[
                            if (mostrarAtalhosRapidos) const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<int>(
                                      value: selecionada.year,
                                      isExpanded: true,
                                      items: anos
                                          .map(
                                            (y) => DropdownMenuItem(
                                              value: y,
                                              child: Text('$y'),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (y) {
                                        if (y != null) {
                                          definirAnoMes(y, selecionada.month);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<int>(
                                      value: selecionada.month,
                                      isExpanded: true,
                                      items: List.generate(12, (i) => i + 1)
                                          .map(
                                            (m) => DropdownMenuItem(
                                              value: m,
                                              child: Text(meses[m - 1]),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (m) {
                                        if (m != null) {
                                          definirAnoMes(selecionada.year, m);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: ColorScheme.light(
                          primary: PainelAdminTheme.roxo,
                          onPrimary: Colors.white,
                          surface: Colors.white,
                          onSurface: PainelAdminTheme.dashboardInk,
                        ),
                        datePickerTheme: DatePickerThemeData(
                          todayBorder: const BorderSide(
                            color: PainelAdminTheme.laranja,
                            width: 2,
                          ),
                          dayForegroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? Colors.white
                                : PainelAdminTheme.dashboardInk,
                          ),
                          dayBackgroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? PainelAdminTheme.roxo
                                : Colors.transparent,
                          ),
                        ),
                      ),
                      child: SizedBox(
                        height: 320,
                        child: CalendarDatePicker(
                          key: ValueKey(
                            '${selecionada.year}-${selecionada.month}-${selecionada.day}',
                          ),
                          initialDate: selecionada,
                          firstDate: min,
                          lastDate: max,
                          onDateChanged: definir,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              'Cancelar',
                              style: GoogleFonts.plusJakartaSans(
                                color: PainelAdminTheme.roxo,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () => Navigator.pop(ctx, selecionada),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Confirmar'),
                            style: FilledButton.styleFrom(
                              backgroundColor: PainelAdminTheme.laranja,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

/// Campo de data premium para formulários do painel.
class DiPertinDateField extends StatelessWidget {
  const DiPertinDateField({
    super.key,
    required this.label,
    required this.data,
    required this.onChanged,
    this.tituloPicker,
    this.subtituloPicker,
    this.dataMinima,
    this.dataMaxima,
    this.destaque = false,
    this.obrigatorio = false,
  });

  final String label;
  final DateTime? data;
  final ValueChanged<DateTime> onChanged;
  final String? tituloPicker;
  final String? subtituloPicker;
  final DateTime? dataMinima;
  final DateTime? dataMaxima;
  final bool destaque;
  final bool obrigatorio;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy', 'pt_BR');
    final preenchido = data != null;
    final accent = destaque ? PainelAdminTheme.laranja : PainelAdminTheme.roxo;

    return InkWell(
      onTap: () async {
        final picked = await showDiPertinDatePicker(
          context,
          titulo: tituloPicker ?? label,
          subtitulo: subtituloPicker,
          dataInicial: data,
          dataMinima: dataMinima,
          dataMaxima: dataMaxima,
        );
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F7FC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: preenchido
                ? accent.withValues(alpha: 0.4)
                : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Icon(
              destaque ? Icons.event_available_outlined : Icons.event_outlined,
              size: 20,
              color: accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                preenchido
                    ? '$label: ${fmt.format(data!)}'
                    : '$label${obrigatorio ? ' *' : ''}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: preenchido ? FontWeight.w700 : FontWeight.w500,
                  color: preenchido
                      ? PainelAdminTheme.dashboardInk
                      : Colors.grey.shade700,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/safe_area_insets.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);
const Color _ink = Color(0xFF1A1A2E);

/// Data civil local (meia-noite) — evita deslocamento de dia da semana por fuso.
DateTime dataSomenteLocal(DateTime d) => DateTime(d.year, d.month, d.day);

String _formatarDiaSemanaLongo(DateTime d) {
  final raw = DateFormat('EEEE', 'pt_BR').format(dataSomenteLocal(d));
  if (raw.isEmpty) return raw;
  return raw[0].toUpperCase() + raw.substring(1);
}

String _formatarDataLongaPtBr(DateTime d) {
  final dia = dataSomenteLocal(d);
  final mes = DateFormat('MMMM', 'pt_BR').format(dia);
  return '${_formatarDiaSemanaLongo(dia)}, ${dia.day} de $mes de ${dia.year}';
}

/// Calendário premium DiPertin (bottom sheet) — pt-BR, atalhos e confirmação.
Future<DateTime?> showDiPertinDatePicker(
  BuildContext context, {
  required String titulo,
  String? subtitulo,
  DateTime? dataInicial,
  DateTime? dataMinima,
  DateTime? dataMaxima,
}) async {
  final agora = DateTime.now();
  final min = dataSomenteLocal(dataMinima ?? DateTime(agora.year - 1, agora.month, agora.day));
  final max = dataSomenteLocal(dataMaxima ?? DateTime(agora.year + 3, agora.month, agora.day));
  var selecionada = dataSomenteLocal(dataInicial ?? agora);
  if (selecionada.isBefore(min)) selecionada = min;
  if (selecionada.isAfter(max)) selecionada = max;

  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final fmtCurto = DateFormat('dd/MM/yyyy', 'pt_BR');

          void definir(DateTime d) {
            var nd = dataSomenteLocal(d);
            if (nd.isBefore(min)) nd = min;
            if (nd.isAfter(max)) nd = max;
            setLocal(() => selecionada = nd);
          }

          Widget chipAtalho(String rotulo, DateTime alvo) {
            final alvoDia = dataSomenteLocal(alvo);
            final ativo = selecionada.year == alvoDia.year &&
                selecionada.month == alvoDia.month &&
                selecionada.day == alvoDia.day;
            return ActionChip(
              label: Text(rotulo),
              avatar: Icon(
                Icons.bolt_rounded,
                size: 16,
                color: ativo ? Colors.white : _laranja,
              ),
              backgroundColor: ativo ? _roxo : Colors.white,
              labelStyle: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: ativo ? Colors.white : _ink,
              ),
              side: BorderSide(
                color: ativo ? _roxo : Colors.grey.shade300,
              ),
              onPressed: () => definir(alvoDia),
            );
          }

          final hoje = dataSomenteLocal(agora);
          final em7 = hoje.add(const Duration(days: 7));
          final em30 = hoje.add(const Duration(days: 30));
          final safeBottom = diPertinSafeAreaBottom(ctx);
          final teclado = MediaQuery.viewInsetsOf(ctx).bottom;
          final alturaTela = MediaQuery.sizeOf(ctx).height;
          final alturaMaxSheet = alturaTela * 0.86 - safeBottom - teclado;
          const alturaRodape = 76.0;
          const alturaHandle = 15.0;
          final alturaScrollMax = (alturaMaxSheet - alturaRodape - alturaHandle)
              .clamp(280.0, alturaMaxSheet);

          final conteudoCalendario = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF4A148C), _roxo, Color(0xFF8E24AA)],
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.calendar_month_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titulo,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          if (subtitulo != null && subtitulo.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitulo,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            _formatarDataLongaPtBr(selecionada),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            fmtCurto.format(selecionada),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    chipAtalho('Hoje', hoje),
                    if (!em7.isAfter(max)) chipAtalho('Em 7 dias', em7),
                    if (!em30.isAfter(max)) chipAtalho('Em 30 dias', em30),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F6FC),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _roxo.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: ColorScheme.light(
                        primary: _roxo,
                        onPrimary: Colors.white,
                        surface: const Color(0xFFF8F6FC),
                        onSurface: _ink,
                      ),
                      datePickerTheme: DatePickerThemeData(
                        backgroundColor: const Color(0xFFF8F6FC),
                        headerBackgroundColor: Colors.transparent,
                        headerForegroundColor: _ink,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        dayStyle: const TextStyle(fontWeight: FontWeight.w600),
                        yearStyle: const TextStyle(fontWeight: FontWeight.w600),
                        todayBorder: const BorderSide(color: _laranja, width: 2),
                        todayForegroundColor:
                            WidgetStateProperty.all(_laranja),
                        dayForegroundColor:
                            WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return Colors.white;
                          }
                          return _ink;
                        }),
                        dayBackgroundColor:
                            WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return _roxo;
                          }
                          return Colors.transparent;
                        }),
                      ),
                    ),
                    child: SizedBox(
                      height: 300,
                      child: CalendarDatePicker(
                        key: ValueKey(
                          '${selecionada.year}-${selecionada.month}',
                        ),
                        initialDate: selecionada,
                        firstDate: min,
                        lastDate: max,
                        onDateChanged: definir,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
          );

          return Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 8 + safeBottom),
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(maxHeight: alturaMaxSheet),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: _roxo.withValues(alpha: 0.22),
                      blurRadius: 36,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: alturaScrollMax),
                      child: SingleChildScrollView(
                        child: conteudoCalendario,
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          top: BorderSide(color: Colors.grey.shade200),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 12,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text(
                              'Cancelar',
                              style: TextStyle(
                                color: _roxo,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () =>
                                  Navigator.pop(ctx, selecionada),
                              icon: const Icon(Icons.check_rounded, size: 20),
                              label: const Text('Confirmar data'),
                              style: FilledButton.styleFrom(
                                backgroundColor: _laranja,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
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

/// Campo de data com visual premium — abre [showDiPertinDatePicker].
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
  });

  final String label;
  final DateTime? data;
  final ValueChanged<DateTime> onChanged;
  final String? tituloPicker;
  final String? subtituloPicker;
  final DateTime? dataMinima;
  final DateTime? dataMaxima;

  /// Borda laranja quando é data de término / campo principal.
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy', 'pt_BR');
    final dataDia = data != null ? dataSomenteLocal(data!) : null;
    final preenchido = dataDia != null;
    final corBorda = destaque ? _laranja : _roxo;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final picked = await showDiPertinDatePicker(
            context,
            titulo: tituloPicker ?? label,
            subtitulo: subtituloPicker,
            dataInicial: dataDia,
            dataMinima: dataMinima,
            dataMaxima: dataMaxima,
          );
          if (picked != null) onChanged(dataSomenteLocal(picked));
        },
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: preenchido
                  ? corBorda.withValues(alpha: 0.45)
                  : Colors.grey.shade300,
              width: preenchido ? 1.5 : 1,
            ),
            boxShadow: preenchido
                ? [
                    BoxShadow(
                      color: corBorda.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        corBorda.withValues(alpha: 0.14),
                        corBorda.withValues(alpha: 0.06),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    destaque
                        ? Icons.event_available_rounded
                        : Icons.event_rounded,
                    color: corBorda,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        preenchido
                            ? fmt.format(dataDia)
                            : 'Toque para escolher',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: preenchido ? _ink : Colors.grey.shade500,
                          letterSpacing: preenchido ? 0.3 : 0,
                        ),
                      ),
                      if (preenchido) ...[
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('EEE', 'pt_BR')
                              .format(dataDia)
                              .toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: corBorda,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade500,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

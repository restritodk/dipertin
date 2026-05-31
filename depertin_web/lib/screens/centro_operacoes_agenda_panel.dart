// Agenda operacional do Centro de operações — calendário + compromissos (staff).
// Dados: coleção Firestore «centro_ops_agenda».

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

// ignore_for_file: deprecated_member_use

import '../theme/painel_admin_theme.dart';

/// Alinhado ao canvas do hub (_CofTheme.canvas).
const Color _agCanvas = Color(0xFFF8FAFC);

String _fmtHoraLocal(BuildContext context, TimeOfDay t) {
  final loc = MaterialLocalizations.of(context);
  final use24 =
      MediaQuery.maybeOf(context)?.alwaysUse24HourFormat ?? true;
  return loc.formatTimeOfDay(t, alwaysUse24HourFormat: use24);
}

bool _ehMesmoDiaCalendario(DateTime? a, DateTime? b) => isSameDay(a, b);

/// Chave alinhada ao grid do [TableCalendar] (`DateTime.utc` com y/m/d do dia civil local).
DateTime _chaveDiaNaAgenda(DateTime instante) {
  final l = instante.toLocal();
  return DateTime.utc(l.year, l.month, l.day);
}

Map<String, dynamic> _mapNorm(Map<String, dynamic>? m) =>
    Map<String, dynamic>.from(m ?? {});

class _AgEvento {
  const _AgEvento({
    required this.id,
    required this.titulo,
    required this.descricao,
    required this.inicio,
    required this.fim,
    required this.diaInteiro,
    required this.tipo,
    required this.prioridade,
    required this.localOuLink,
    required this.participantes,
    required this.status,
    required this.lembreteMinutos,
  });

  final String id;
  final String titulo;
  final String descricao;
  final DateTime inicio;
  final DateTime fim;
  final bool diaInteiro;
  final String tipo;
  final String prioridade;
  final String localOuLink;
  final String participantes;
  final String status;
  final int? lembreteMinutos;

  factory _AgEvento.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = _mapNorm(doc.data());
    final ti = m['inicio'];
    final tf = m['fim'];
    final inicio = ti is Timestamp
        ? ti.toDate()
        : DateTime.now();
    final fim = tf is Timestamp ? tf.toDate() : inicio.add(const Duration(hours: 1));
    return _AgEvento(
      id: doc.id,
      titulo: (m['titulo'] ?? '').toString().trim().isEmpty
          ? 'Sem título'
          : (m['titulo'] ?? '').toString().trim(),
      descricao: (m['descricao'] ?? '').toString(),
      inicio: inicio,
      fim: fim,
      diaInteiro: m['dia_inteiro'] == true,
      tipo: (m['tipo'] ?? 'reuniao').toString(),
      prioridade: (m['prioridade'] ?? 'media').toString(),
      localOuLink: (m['local_ou_link'] ?? '').toString(),
      participantes: (m['participantes'] ?? '').toString(),
      status: (m['status'] ?? 'pendente').toString(),
      lembreteMinutos: m['lembrete_minutos'] is int
          ? m['lembrete_minutos'] as int
          : int.tryParse('${m['lembrete_minutos'] ?? ''}'),
    );
  }

  bool get concluidoOuCancelado {
    final s = status.toLowerCase();
    return s == 'concluido' || s == 'cancelado';
  }

  Color get corTipo {
    switch (tipo) {
      case 'tarefa':
        return const Color(0xFF0D9488);
      case 'lembrete':
        return const Color(0xFFD97706);
      case 'bloqueio':
        return const Color(0xFF64748B);
      default:
        return const Color(0xFF4F46E5);
    }
  }

  String get rotuloTipo {
    switch (tipo) {
      case 'tarefa':
        return 'Tarefa';
      case 'lembrete':
        return 'Lembrete';
      case 'bloqueio':
        return 'Bloqueio';
      default:
        return 'Reunião';
    }
  }
}

Map<DateTime, List<_AgEvento>> _agruparPorDia(Iterable<_AgEvento> eventos) {
  final map = <DateTime, List<_AgEvento>>{};
  for (final e in eventos) {
    final k = _chaveDiaNaAgenda(e.inicio);
    map.putIfAbsent(k, () => []).add(e);
  }
  for (final list in map.values) {
    list.sort((a, b) => a.inicio.compareTo(b.inicio));
  }
  return map;
}

class PainelCentroOpsAgenda extends StatefulWidget {
  const PainelCentroOpsAgenda({super.key});

  @override
  State<PainelCentroOpsAgenda> createState() => _PainelCentroOpsAgendaState();
}

class _PainelCentroOpsAgendaState extends State<PainelCentroOpsAgenda> {
  static final _fmtDia = DateFormat("EEEE, d 'de' MMMM", 'pt_BR');
  static final _fmtHora = DateFormat('HH:mm');
  static final _fmtDataHora = DateFormat('dd/MM/yyyy HH:mm');

  late DateTime _focusedDay;
  late DateTime _selectedDay;
  CalendarFormat _calFormat = CalendarFormat.month;
  String? _filtroTipo;

  @override
  void initState() {
    super.initState();
    final hoje = normalizeDate(DateTime.now());
    _focusedDay = hoje;
    _selectedDay = hoje;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamAgenda() {
    return FirebaseFirestore.instance
        .collection('centro_ops_agenda')
        .orderBy('inicio')
        .limit(500)
        .snapshots();
  }

  Iterable<_AgEvento> _aplicarFiltro(Iterable<_AgEvento> todos) {
    final f = _filtroTipo;
    if (f == null) return todos;
    return todos.where((e) => e.tipo == f);
  }

  Future<void> _abrirEditor({String? docId, _AgEvento? existente}) async {
    final tituloC = TextEditingController(text: existente?.titulo ?? '');
    final descC = TextEditingController(text: existente?.descricao ?? '');
    final localC = TextEditingController(text: existente?.localOuLink ?? '');
    final partC = TextEditingController(text: existente?.participantes ?? '');
    String tipo = existente?.tipo ?? 'reuniao';
    String prioridade = existente?.prioridade ?? 'media';
    String status = existente?.status ?? 'pendente';
    bool diaInteiro = existente?.diaInteiro ?? false;
    int? lembrete = existente?.lembreteMinutos;

    var dataRef = existente != null
        ? DateTime(
            existente.inicio.year,
            existente.inicio.month,
            existente.inicio.day,
          )
        : DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    TimeOfDay horaInicio = existente != null && !existente.diaInteiro
        ? TimeOfDay.fromDateTime(existente.inicio.toLocal())
        : const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay horaFim = existente != null && !existente.diaInteiro
        ? TimeOfDay.fromDateTime(existente.fim.toLocal())
        : const TimeOfDay(hour: 10, minute: 0);

    if (!mounted) return;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            Future<void> pickData() async {
              final d = await showDatePicker(
                context: ctx,
                initialDate: dataRef,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035, 12, 31),
                locale: const Locale('pt', 'BR'),
              );
              if (d != null) setD(() => dataRef = DateTime(d.year, d.month, d.day));
            }

            Future<void> pickHora(bool inicio) async {
              final t = await showTimePicker(
                context: ctx,
                initialTime: inicio ? horaInicio : horaFim,
              );
              if (t != null) {
                setD(() {
                  if (inicio) {
                    horaInicio = t;
                  } else {
                    horaFim = t;
                  }
                });
              }
            }

            DateTime combinar(DateTime dia, TimeOfDay t) => DateTime(
                  dia.year,
                  dia.month,
                  dia.day,
                  t.hour,
                  t.minute,
                );

            Future<void> salvar() async {
              if (tituloC.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Informe o título.')),
                );
                return;
              }
              late DateTime ini;
              late DateTime fim;
              if (diaInteiro) {
                ini = DateTime(dataRef.year, dataRef.month, dataRef.day);
                fim = DateTime(dataRef.year, dataRef.month, dataRef.day, 23, 59);
              } else {
                ini = combinar(dataRef, horaInicio);
                fim = combinar(dataRef, horaFim);
                if (!fim.isAfter(ini)) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('O término deve ser após o início.'),
                    ),
                  );
                  return;
                }
              }

              final u = FirebaseAuth.instance.currentUser;
              final col = FirebaseFirestore.instance.collection('centro_ops_agenda');
              final payload = <String, dynamic>{
                'titulo': tituloC.text.trim(),
                'descricao': descC.text.trim(),
                'inicio': Timestamp.fromDate(ini.toUtc()),
                'fim': Timestamp.fromDate(fim.toUtc()),
                'dia_inteiro': diaInteiro,
                'tipo': tipo,
                'prioridade': prioridade,
                'local_ou_link': localC.text.trim(),
                'participantes': partC.text.trim(),
                'status': status,
                'lembrete_minutos': lembrete,
                'atualizado_em': FieldValue.serverTimestamp(),
              };

              try {
                if (docId == null) {
                  payload['criado_em'] = FieldValue.serverTimestamp();
                  if (u != null) payload['criado_por_uid'] = u.uid;
                  if (u?.email != null && u!.email!.isNotEmpty) {
                    payload['criado_por_email'] = u.email;
                  }
                  await col.add(payload);
                } else {
                  await col.doc(docId).update(payload);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao salvar: $e'),
                      backgroundColor: Colors.red.shade800,
                    ),
                  );
                }
              }
            }

            final decLabel = InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            );

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
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
                              Icons.event_available_rounded,
                              color: PainelAdminTheme.roxo,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              docId == null ? 'Novo compromisso' : 'Editar',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: PainelAdminTheme.dashboardInk,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: tituloC,
                        decoration: decLabel.copyWith(labelText: 'Título *'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: tipo,
                        decoration: decLabel.copyWith(labelText: 'Tipo'),
                        items: const [
                          DropdownMenuItem(value: 'reuniao', child: Text('Reunião')),
                          DropdownMenuItem(value: 'tarefa', child: Text('Tarefa')),
                          DropdownMenuItem(value: 'lembrete', child: Text('Lembrete')),
                          DropdownMenuItem(value: 'bloqueio', child: Text('Bloqueio de agenda')),
                        ],
                        onChanged: (v) => setD(() => tipo = v ?? 'reuniao'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: prioridade,
                              decoration: decLabel.copyWith(labelText: 'Prioridade'),
                              items: const [
                                DropdownMenuItem(value: 'baixa', child: Text('Baixa')),
                                DropdownMenuItem(value: 'media', child: Text('Média')),
                                DropdownMenuItem(value: 'alta', child: Text('Alta')),
                              ],
                              onChanged: (v) => setD(() => prioridade = v ?? 'media'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: status,
                              decoration: decLabel.copyWith(labelText: 'Status'),
                              items: const [
                                DropdownMenuItem(value: 'pendente', child: Text('Pendente')),
                                DropdownMenuItem(value: 'concluido', child: Text('Concluído')),
                                DropdownMenuItem(value: 'cancelado', child: Text('Cancelado')),
                              ],
                              onChanged: (v) => setD(() => status = v ?? 'pendente'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        value: diaInteiro,
                        onChanged: (v) => setD(() => diaInteiro = v),
                        title: const Text('Dia inteiro'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Data'),
                        subtitle: Text(DateFormat('dd/MM/yyyy').format(dataRef)),
                        trailing: const Icon(Icons.calendar_today_outlined),
                        onTap: pickData,
                      ),
                      if (!diaInteiro) ...[
                        Row(
                          children: [
                            Expanded(
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Início'),
                                subtitle: Text(_fmtHoraLocal(ctx, horaInicio)),
                                onTap: () => pickHora(true),
                              ),
                            ),
                            Expanded(
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Término'),
                                subtitle: Text(_fmtHoraLocal(ctx, horaFim)),
                                onTap: () => pickHora(false),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextField(
                        controller: localC,
                        decoration: decLabel.copyWith(
                          labelText: 'Local ou link (Meet, Teams…)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: partC,
                        decoration: decLabel.copyWith(
                          labelText: 'Participantes',
                          hintText: 'Nomes ou e-mails, separados por vírgula',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int?>(
                        value: lembrete,
                        decoration: decLabel.copyWith(
                          labelText: 'Alerta antes (somente registro)',
                        ),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Sem alerta')),
                          DropdownMenuItem(value: 15, child: Text('15 minutos')),
                          DropdownMenuItem(value: 60, child: Text('1 hora')),
                          DropdownMenuItem(value: 1440, child: Text('1 dia')),
                        ],
                        onChanged: (v) => setD(() => lembrete = v),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descC,
                        maxLines: 4,
                        decoration: decLabel.copyWith(
                          labelText: 'Observações / pauta',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: salvar,
                            icon: const Icon(Icons.check_rounded, size: 20),
                            label: const Text('Salvar'),
                            style: FilledButton.styleFrom(
                              backgroundColor: PainelAdminTheme.roxo,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
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
    } finally {
      tituloC.dispose();
      descC.dispose();
      localC.dispose();
      partC.dispose();
    }
  }

  Future<void> _remover(String id, String titulo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir compromisso?'),
        content: Text('«$titulo» será removido permanentemente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await FirebaseFirestore.instance
          .collection('centro_ops_agenda')
          .doc(id)
          .delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _streamAgenda(),
      builder: (context, snap) {
        final carregando =
            snap.connectionState == ConnectionState.waiting && !snap.hasData;
        final docs = snap.data?.docs ?? [];
        final todos = docs.map(_AgEvento.fromDoc).toList();
        final filtrados = _aplicarFiltro(todos).toList();
        final mapa = _agruparPorDia(filtrados);
        final eventosDia = List<_AgEvento>.from(
          mapa[_selectedDay] ?? [],
        );

        final proximos = filtrados
            .where((e) => !e.concluidoOuCancelado && !e.fim.isBefore(DateTime.now()))
            .toList()
          ..sort((a, b) => a.inicio.compareTo(b.inicio));

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 48),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Agenda operacional',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: PainelAdminTheme.dashboardInk,
                                    letterSpacing: -0.4,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Planeje reuniões, tarefas e bloqueios da equipe. '
                              'Sincronizado em tempo real no Firestore (apenas staff).',
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.45,
                                color: PainelAdminTheme.textoSecundario,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: carregando ? null : () => _abrirEditor(),
                        icon: const Icon(Icons.add_rounded, size: 22),
                        label: const Text('Novo compromisso'),
                        style: FilledButton.styleFrom(
                          backgroundColor: PainelAdminTheme.roxo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (snap.hasError) ...[
                    const SizedBox(height: 16),
                    Material(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          'Erro ao carregar agenda: ${snap.error}',
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Filtrar:',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: PainelAdminTheme.dashboardInk,
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('Todos'),
                        selected: _filtroTipo == null,
                        onSelected: (_) =>
                            setState(() => _filtroTipo = null),
                      ),
                      ChoiceChip(
                        label: const Text('Reuniões'),
                        selected: _filtroTipo == 'reuniao',
                        onSelected: (_) =>
                            setState(() => _filtroTipo = 'reuniao'),
                      ),
                      ChoiceChip(
                        label: const Text('Tarefas'),
                        selected: _filtroTipo == 'tarefa',
                        onSelected: (_) =>
                            setState(() => _filtroTipo = 'tarefa'),
                      ),
                      ChoiceChip(
                        label: const Text('Lembretes'),
                        selected: _filtroTipo == 'lembrete',
                        onSelected: (_) =>
                            setState(() => _filtroTipo = 'lembrete'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, c) {
                      final largo = c.maxWidth >= 1020;
                      final calCard = _AgCalCard(
                        carregando: carregando,
                        focusedDay: _focusedDay,
                        selectedDay: _selectedDay,
                        calFormat: _calFormat,
                        eventLoader: (day) =>
                            mapa[normalizeDate(day)] ?? const [],
                        onDaySelected: (s, f) => setState(() {
                          _selectedDay = normalizeDate(s);
                          _focusedDay = normalizeDate(f);
                        }),
                        onPageChanged: (f) =>
                            setState(() => _focusedDay = normalizeDate(f)),
                        onFormatChanged: (f) =>
                            setState(() => _calFormat = f),
                      );

                      final painel = _AgDetalhesDia(
                        fmtDiaSemana: _fmtDia,
                        fmtHora: _fmtHora,
                        fmtDataHora: _fmtDataHora,
                        dia: _selectedDay,
                        lista: eventosDia,
                        proximosTop: proximos.take(8).toList(),
                        aoEditar: (e) => _abrirEditor(docId: e.id, existente: e),
                        aoExcluir: _remover,
                        aoMarcarConcluido: (id) async {
                          try {
                            await FirebaseFirestore.instance
                                .collection('centro_ops_agenda')
                                .doc(id)
                                .update({
                              'status': 'concluido',
                              'atualizado_em': FieldValue.serverTimestamp(),
                            });
                          } catch (_) {}
                        },
                      );

                      if (!largo) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            calCard,
                            const SizedBox(height: 18),
                            painel,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 55, child: calCard),
                          const SizedBox(width: 22),
                          Expanded(flex: 45, child: painel),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AgCalCard extends StatelessWidget {
  const _AgCalCard({
    required this.carregando,
    required this.focusedDay,
    required this.selectedDay,
    required this.calFormat,
    required this.eventLoader,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.onFormatChanged,
  });

  final bool carregando;
  final DateTime focusedDay;
  final DateTime selectedDay;
  final CalendarFormat calFormat;
  final List<_AgEvento> Function(DateTime day) eventLoader;
  final void Function(DateTime s, DateTime f) onDaySelected;
  final void Function(DateTime f) onPageChanged;
  final void Function(CalendarFormat f) onFormatChanged;

  @override
  Widget build(BuildContext context) {
    final roxo = PainelAdminTheme.roxo;

    final cal = TableCalendar<_AgEvento>(
      locale: 'pt_BR',
      focusedDay: focusedDay,
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2035, 12, 31),
      calendarFormat: calFormat,
      availableCalendarFormats: const {
        CalendarFormat.month: 'Mês',
        CalendarFormat.twoWeeks: '2 semanas',
        CalendarFormat.week: 'Semana',
      },
      startingDayOfWeek: StartingDayOfWeek.monday,
      selectedDayPredicate: (day) =>
          _ehMesmoDiaCalendario(normalizeDate(day), selectedDay),
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
      onFormatChanged: onFormatChanged,
      eventLoader: eventLoader,
      currentDay: normalizeDate(DateTime.now()),
      calendarBuilders: CalendarBuilders(
        markerBuilder: (ctx, day, events) {
          if (events.isEmpty) return null;
          return Positioned(
            bottom: 2,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < events.length.clamp(0, 4); i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.2),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: events[i].corTipo,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      calendarStyle: CalendarStyle(
        todayDecoration: BoxDecoration(
          color: PainelAdminTheme.laranja.withValues(alpha: 0.22),
          shape: BoxShape.circle,
          border: Border.all(
            color: PainelAdminTheme.laranja.withValues(alpha: 0.85),
          ),
        ),
        selectedDecoration: BoxDecoration(
          color: roxo.withValues(alpha: 0.9),
          shape: BoxShape.circle,
        ),
        selectedTextStyle:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        todayTextStyle:
            TextStyle(color: Colors.grey.shade900, fontWeight: FontWeight.w800),
        weekendTextStyle:
            TextStyle(color: Colors.blueGrey.shade600, fontWeight: FontWeight.w600),
        markersMaxCount: 4,
      ),
      headerStyle: HeaderStyle(
        formatButtonVisible: true,
        titleCentered: true,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              PainelAdminTheme.dashboardInk.withValues(alpha: 0.06),
              roxo.withValues(alpha: 0.05),
            ],
          ),
        ),
        leftChevronIcon: Icon(Icons.chevron_left_rounded, color: roxo),
        rightChevronIcon: Icon(Icons.chevron_right_rounded, color: roxo),
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        weekendStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.blueGrey.shade700,
          fontSize: 12,
        ),
        weekdayStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.blueGrey.shade800,
          fontSize: 12,
        ),
      ),
    );

    return Stack(
      children: [
        Material(
          color: Colors.white,
          elevation: 1,
          shadowColor: Colors.black.withValues(alpha: 0.07),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.blueGrey.withValues(alpha: 0.12)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 14),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Calendário',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.05,
                        color: PainelAdminTheme.textoSecundario,
                      ),
                    ),
                  ),
                ),
                cal,
              ],
            ),
          ),
        ),
        if (carregando)
          Positioned.fill(
            child: Container(
              color: Colors.white.withValues(alpha: 0.72),
              child: Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(color: roxo),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AgDetalhesDia extends StatelessWidget {
  const _AgDetalhesDia({
    required this.fmtDiaSemana,
    required this.fmtHora,
    required this.fmtDataHora,
    required this.dia,
    required this.lista,
    required this.proximosTop,
    required this.aoEditar,
    required this.aoExcluir,
    required this.aoMarcarConcluido,
  });

  final DateFormat fmtDiaSemana;
  final DateFormat fmtHora;
  final DateFormat fmtDataHora;
  final DateTime dia;
  final List<_AgEvento> lista;
  final List<_AgEvento> proximosTop;
  final void Function(_AgEvento e) aoEditar;
  final Future<void> Function(String id, String titulo) aoExcluir;
  final void Function(String id) aoMarcarConcluido;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: PainelAdminTheme.dashboardInk,
          elevation: 0,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dia selecionado',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _capitalizarTitulo(
                    fmtDiaSemana.format(
                      DateTime(dia.year, dia.month, dia.day),
                    ),
                  ),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${lista.length} compromisso(s) neste dia',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Material(
          color: Colors.white,
          elevation: 1,
          shadowColor: Colors.black.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.blueGrey.withValues(alpha: 0.1)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 260),
            child: lista.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.event_note_rounded,
                            size: 48,
                            color: Colors.blueGrey.shade300,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Nada agendado para este dia.\nUse «Novo compromisso». ',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.blueGrey.shade600,
                              fontSize: 14,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 14),
                    itemCount: lista.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = lista[i];
                      return _LinhaAgendaTile(
                        e: e,
                        fmtHora: fmtHora,
                        aoEditar: () => aoEditar(e),
                        aoExcluir: () => aoExcluir(e.id, e.titulo),
                        aoMarcarConcluido: () => aoMarcarConcluido(e.id),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Próximos na fila',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: PainelAdminTheme.dashboardInk,
              ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Itens em aberto ordenados pela data.',
          style: TextStyle(fontSize: 12.5, color: PainelAdminTheme.textoSecundario),
        ),
        const SizedBox(height: 10),
        Material(
          color: _agCanvas,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: PainelAdminTheme.roxo.withValues(alpha: 0.12)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: proximosTop.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'Nenhum compromisso pendente à frente nesta amostra.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.blueGrey.shade600),
                    ),
                  )
                : Column(
                    children: [
                      for (final e in proximosTop)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: InkWell(
                            onTap: () => aoEditar(e),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  Container(
                                    width: 4,
                                    constraints: const BoxConstraints(minHeight: 36),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      color: e.corTipo,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.titulo,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${e.rotuloTipo} · '
                                          '${fmtDataHora.format(e.inicio.toLocal())}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.blueGrey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                    color: PainelAdminTheme.roxo.withValues(alpha: 0.7),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

String _capitalizarTitulo(String texto) {
  if (texto.isEmpty) return texto;
  return texto[0].toUpperCase() + texto.substring(1);
}

class _LinhaAgendaTile extends StatelessWidget {
  const _LinhaAgendaTile({
    required this.e,
    required this.fmtHora,
    required this.aoEditar,
    required this.aoExcluir,
    required this.aoMarcarConcluido,
  });

  final _AgEvento e;
  final DateFormat fmtHora;
  final VoidCallback aoEditar;
  final VoidCallback aoExcluir;
  final VoidCallback aoMarcarConcluido;

  @override
  Widget build(BuildContext context) {
    final cortado =
        TextStyle(decoration: TextDecoration.lineThrough, color: Colors.blueGrey.shade500);
    final hora = e.diaInteiro
        ? 'Dia inteiro'
        : '${fmtHora.format(e.inicio.toLocal())} – ${fmtHora.format(e.fim.toLocal())}';

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Container(
        width: 10,
        height: 44,
        decoration: BoxDecoration(
          color: e.corTipo,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      title: Text(
        e.titulo,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          decoration:
              e.concluidoOuCancelado ? TextDecoration.lineThrough : null,
          color:
              e.concluidoOuCancelado ? Colors.blueGrey.shade500 : PainelAdminTheme.dashboardInk,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            '${e.rotuloTipo} · $hora · ${e.status}',
            style: e.concluidoOuCancelado ? cortado : null,
          ),
          if (e.localOuLink.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '📍 ${e.localOuLink}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          if (!e.concluidoOuCancelado)
            IconButton(
              tooltip: 'Marcar concluído',
              icon: Icon(
                Icons.check_circle_outline_rounded,
                color: Colors.green.shade700,
              ),
              onPressed: aoMarcarConcluido,
            ),
          IconButton(
            tooltip: 'Editar',
            icon: Icon(Icons.edit_outlined, color: PainelAdminTheme.roxo),
            onPressed: aoEditar,
          ),
          IconButton(
            tooltip: 'Excluir',
            icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
            onPressed: aoExcluir,
          ),
        ],
      ),
    );
  }
}

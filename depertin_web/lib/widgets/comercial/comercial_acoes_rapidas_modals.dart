import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/models/comercial_pendencia_data.dart';
import 'package:depertin_web/services/comercial_pendencias_service.dart';
import 'package:depertin_web/services/firebase_functions_config.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

// =============================================================================
// Ações Rápidas — Pendência Financeira (lembretes + gerar cobranças)
// =============================================================================

const Color _kRoxo = Color(0xFF6A1B9A);
const Color _kLaranja = Color(0xFFFF8F00);
const Color _kTexto = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF64748B);
const Color _kFundo = Color(0xFFF5F4F8);
const int _kPageSize = 10;

enum _EnvioStatus { pendente, enviando, sucesso, parcial, falha, pulado }

class _CanalInfo {
  const _CanalInfo(this.id, this.label, this.icone, this.cor);
  final String id;
  final String label;
  final IconData icone;
  final Color cor;
}

const _kCanaisMeta = <_CanalInfo>[
  _CanalInfo('whatsapp', 'WhatsApp', Icons.chat_rounded, Color(0xFF25D366)),
  _CanalInfo('email', 'E-mail', Icons.email_rounded, Color(0xFF2563EB)),
  _CanalInfo('sms', 'SMS', Icons.sms_rounded, _kRoxo),
];

class _ClienteAcaoRow {
  _ClienteAcaoRow({
    required this.clienteId,
    required this.nome,
    required this.parcelaLabel,
    required this.valor,
    required this.vencimento,
    required this.diasAtraso,
    this.telefone,
    this.whatsapp,
    this.email,
  });

  final String clienteId;
  final String nome;
  final String parcelaLabel;
  final double valor;
  final DateTime vencimento;
  final int diasAtraso;
  final String? telefone;
  final String? whatsapp;
  final String? email;

  _EnvioStatus status = _EnvioStatus.pendente;
  String detalhe = '';
  final Map<String, String> resultadoCanais = {};
}

/// Abre modal de lembretes para clientes com parcelas em atraso.
Future<void> abrirModalEnviarLembretes({
  required BuildContext context,
  required String lojaId,
  required List<PendenciaFinanceiraCliente> itens,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _AcoesRapidasModal(
      lojaId: lojaId,
      modo: _ModoAcao.lembretes,
      itensBase: itens,
    ),
  );
}

/// Abre modal de gerar cobranças (atraso > 3 dias) com seleção e canal.
Future<void> abrirModalGerarCobrancas({
  required BuildContext context,
  required String lojaId,
  required List<PendenciaFinanceiraCliente> itens,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _AcoesRapidasModal(
      lojaId: lojaId,
      modo: _ModoAcao.cobrancas,
      itensBase: itens,
    ),
  );
}

enum _ModoAcao { lembretes, cobrancas }

enum _FaseModal { lista, canal, processando, relatorio }

// =============================================================================

class _AcoesRapidasModal extends StatefulWidget {
  const _AcoesRapidasModal({
    required this.lojaId,
    required this.modo,
    required this.itensBase,
  });

  final String lojaId;
  final _ModoAcao modo;
  final List<PendenciaFinanceiraCliente> itensBase;

  @override
  State<_AcoesRapidasModal> createState() => _AcoesRapidasModalState();
}

class _AcoesRapidasModalState extends State<_AcoesRapidasModal>
    with SingleTickerProviderStateMixin {
  final _dataFmt = DateFormat('dd/MM/yyyy', 'pt_BR');
  late final AnimationController _pulse;

  _FaseModal _fase = _FaseModal.lista;
  bool _carregandoCanais = true;
  final Map<String, bool> _canaisConfigurados = {};
  List<_ClienteAcaoRow> _rows = [];
  final Set<String> _selecionados = {};
  String? _canalEscolhido;
  int _pagina = 1;
  int _progressoAtual = 0;
  int _okCount = 0;
  int _failCount = 0;
  int _skipCount = 0;

  bool get _ehLembrete => widget.modo == _ModoAcao.lembretes;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _rows = _montarRows();
    if (!_ehLembrete) {
      for (final r in _rows) {
        _selecionados.add(r.clienteId);
      }
    }
    _carregarCanais();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  List<_ClienteAcaoRow> _montarRows() {
    final hoje = DateTime.now();
    final hojeClean = DateTime(hoje.year, hoje.month, hoje.day);
    final out = <_ClienteAcaoRow>[];

    for (final item in widget.itensBase) {
      final vencidas = item.parcelasVencidas.where((p) {
        if (!_ehLembrete) {
          final venc = DateTime(
            p.dataVencimento.year,
            p.dataVencimento.month,
            p.dataVencimento.day,
          );
          return hojeClean.difference(venc).inDays > 3;
        }
        return true;
      }).toList();
      if (vencidas.isEmpty) continue;

      vencidas.sort((a, b) => a.dataVencimento.compareTo(b.dataVencimento));
      final maisAntiga = vencidas.first;
      final valor = vencidas.fold<double>(0, (s, p) => s + p.valorEmAberto);
      final dias = hojeClean
          .difference(DateTime(
            maisAntiga.dataVencimento.year,
            maisAntiga.dataVencimento.month,
            maisAntiga.dataVencimento.day,
          ))
          .inDays;

      String parcelaLabel;
      if (vencidas.length == 1) {
        final p = vencidas.first;
        parcelaLabel = 'Parcela ${p.numeroParcela}';
        if (p.codigoVenda.isNotEmpty) {
          parcelaLabel = '$parcelaLabel · ${p.codigoVenda}';
        }
      } else {
        parcelaLabel = '${vencidas.length} parcelas em atraso';
      }

      out.add(_ClienteAcaoRow(
        clienteId: item.clienteId,
        nome: item.clienteNome,
        parcelaLabel: parcelaLabel,
        valor: valor,
        vencimento: maisAntiga.dataVencimento,
        diasAtraso: dias,
        telefone: item.clienteTelefone,
        whatsapp: item.clienteWhatsApp ?? item.clienteTelefone,
        email: item.clienteEmail,
      ));
    }

    out.sort((a, b) => b.diasAtraso.compareTo(a.diasAtraso));
    return out;
  }

  Future<void> _carregarCanais() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('gestao_comercial_configuracoes')
          .doc(widget.lojaId)
          .get();
      final cobranca =
          (snap.data() ?? {})['cobranca'] as Map<String, dynamic>? ?? {};

      final w = cobranca['whatsapp'] as Map<String, dynamic>? ?? {};
      final s = cobranca['sms'] as Map<String, dynamic>? ?? {};
      final e = cobranca['email'] as Map<String, dynamic>? ?? {};
      final et = e['emailTransacional'] as Map<String, dynamic>? ?? {};

      final waAtivo = w['ativo'] == true &&
          ((w['provedor']?.toString() == 'vzaps' &&
                  (w['instanceId']?.toString().trim().isNotEmpty ?? false)) ||
              (w['apiUrl']?.toString().trim().isNotEmpty ?? false) ||
              (w['token']?.toString().trim().isNotEmpty ?? false));

      final smsAtivo = s['ativo'] == true &&
          (s['token']?.toString().trim().isNotEmpty ?? false);

      final modoEmail = (et['modoIntegracao'] ?? '').toString().trim();
      final emailAtivo = modoEmail.isNotEmpty || e['ativo'] == true;

      if (!mounted) return;
      setState(() {
        _canaisConfigurados['whatsapp'] = waAtivo;
        _canaisConfigurados['sms'] = smsAtivo;
        _canaisConfigurados['email'] = emailAtivo;
        _carregandoCanais = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregandoCanais = false);
    }
  }

  List<String> _canaisDisponiveisPara(_ClienteAcaoRow row) {
    final list = <String>[];
    if (_canaisConfigurados['whatsapp'] == true &&
        (row.whatsapp?.trim().isNotEmpty ?? false)) {
      list.add('whatsapp');
    }
    if (_canaisConfigurados['email'] == true &&
        (row.email?.trim().isNotEmpty ?? false)) {
      list.add('email');
    }
    if (_canaisConfigurados['sms'] == true &&
        ((row.telefone?.trim().isNotEmpty ?? false) ||
            (row.whatsapp?.trim().isNotEmpty ?? false))) {
      list.add('sms');
    }
    return list;
  }

  List<_ClienteAcaoRow> get _paginaAtual {
    final start = (_pagina - 1) * _kPageSize;
    if (start >= _rows.length) return const [];
    final end = (start + _kPageSize).clamp(0, _rows.length);
    return _rows.sublist(start, end);
  }

  int get _totalPaginas =>
      _rows.isEmpty ? 1 : ((_rows.length - 1) ~/ _kPageSize) + 1;

  Future<void> _iniciarEnvioLembretes() async {
    final alvos = _rows.where((r) => _canaisDisponiveisPara(r).isNotEmpty).toList();
    if (alvos.isEmpty) {
      setState(() {
        _fase = _FaseModal.relatorio;
        _skipCount = _rows.length;
      });
      return;
    }
    setState(() {
      _fase = _FaseModal.processando;
      _progressoAtual = 0;
      _okCount = 0;
      _failCount = 0;
      _skipCount = 0;
      for (final r in _rows) {
        r.status = _EnvioStatus.pendente;
        r.detalhe = '';
        r.resultadoCanais.clear();
      }
    });
    await _processarEnvios(
      alvos,
      (row) => _canaisDisponiveisPara(row),
    );
  }

  Future<void> _iniciarEnvioCobrancas() async {
    if (_canalEscolhido == null) return;
    final alvos = _rows
        .where((r) => _selecionados.contains(r.clienteId))
        .where((r) => _canaisDisponiveisPara(r).contains(_canalEscolhido))
        .toList();
    final pulados = _rows
        .where((r) => _selecionados.contains(r.clienteId))
        .where((r) => !_canaisDisponiveisPara(r).contains(_canalEscolhido))
        .toList();
    for (final p in pulados) {
      p.status = _EnvioStatus.pulado;
      p.detalhe = 'Sem contato para o canal ${_labelCanal(_canalEscolhido!)}';
    }
    setState(() {
      _fase = _FaseModal.processando;
      _progressoAtual = 0;
      _okCount = 0;
      _failCount = 0;
      _skipCount = pulados.length;
    });
    await _processarEnvios(alvos, (_) => [_canalEscolhido!]);
  }

  Future<void> _processarEnvios(
    List<_ClienteAcaoRow> alvos,
    List<String> Function(_ClienteAcaoRow) canaisOf,
  ) async {
    for (var i = 0; i < alvos.length; i++) {
      final row = alvos[i];
      if (!mounted) return;
      setState(() {
        row.status = _EnvioStatus.enviando;
        row.detalhe = 'Enviando...';
        _progressoAtual = i + 1;
      });

      final canais = canaisOf(row);
      try {
        final result = await callFirebaseFunctionSafe(
          'gestaoComercialEnviarComunicacao',
          region: kFirebaseFunctionsRegionSouth,
          parameters: {
            'lojaId': widget.lojaId,
            'clienteId': row.clienteId,
            'tipo': 'cobranca',
            'canais': canais,
          },
        );
        final resultados = (result['resultados'] as List<dynamic>?) ?? [];
        var ok = 0;
        var fail = 0;
        final buf = <String>[];
        for (final raw in resultados) {
          if (raw is! Map) continue;
          final canal = raw['canal']?.toString() ?? '';
          final sucesso = raw['ok'] == true;
          final erro = raw['erro']?.toString().trim();
          row.resultadoCanais[canal] =
              sucesso ? 'Enviado com sucesso' : (erro?.isNotEmpty == true ? erro! : 'Falha no envio');
          if (sucesso) {
            ok++;
            buf.add('${_labelCanal(canal)}: ok');
          } else {
            fail++;
            buf.add('${_labelCanal(canal)}: ${erro ?? 'falha'}');
          }
        }
        if (!mounted) return;
        setState(() {
          if (ok > 0 && fail == 0) {
            row.status = _EnvioStatus.sucesso;
            row.detalhe = 'Enviado com sucesso';
            _okCount++;
          } else if (ok > 0 && fail > 0) {
            row.status = _EnvioStatus.parcial;
            row.detalhe = buf.join(' · ');
            _okCount++;
            _failCount++;
          } else {
            row.status = _EnvioStatus.falha;
            row.detalhe = buf.isEmpty ? 'Falha no envio' : buf.join(' · ');
            _failCount++;
          }
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          row.status = _EnvioStatus.falha;
          row.detalhe = e is CallableHttpException
              ? mensagemCallableHttpException(e)
              : e.toString();
          _failCount++;
        });
      }
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }

    // Marca quem ficou sem canal como pulado (lembretes)
    if (_ehLembrete) {
      for (final r in _rows) {
        if (r.status == _EnvioStatus.pendente) {
          r.status = _EnvioStatus.pulado;
          r.detalhe = 'Sem canal disponível (contato ou integração)';
          _skipCount++;
        }
      }
    }

    if (!mounted) return;
    setState(() => _fase = _FaseModal.relatorio);
  }

  String _labelCanal(String id) {
    for (final c in _kCanaisMeta) {
      if (c.id == id) return c.label;
    }
    return id;
  }

  void _fechar() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final titulo = _ehLembrete ? 'Enviar lembretes' : 'Gerar cobranças';
    final subtitulo = _ehLembrete
        ? 'Clientes com parcelas em atraso'
        : 'Clientes com mais de 3 dias de atraso';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          elevation: 24,
          child: Column(
            children: [
              _buildHeader(titulo, subtitulo),
              Expanded(child: _buildBody()),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String titulo, String subtitulo) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 12, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kRoxo, Color(0xFF8E24AA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _ehLembrete ? Icons.notifications_active_rounded : Icons.receipt_long_rounded,
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
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          if (_fase != _FaseModal.processando)
            IconButton(
              onPressed: _fechar,
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_carregandoCanais) {
      return const Center(
        child: CircularProgressIndicator(color: _kRoxo),
      );
    }
    switch (_fase) {
      case _FaseModal.lista:
        return _buildLista();
      case _FaseModal.canal:
        return _buildEscolhaCanal();
      case _FaseModal.processando:
        return _buildProcessando();
      case _FaseModal.relatorio:
        return _buildRelatorio();
    }
  }

  Widget _buildLista() {
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_rounded, size: 48, color: _kMuted.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                _ehLembrete
                    ? 'Nenhum cliente com parcela em atraso.'
                    : 'Nenhum cliente com mais de 3 dias de atraso.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _kMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_rows.length} cliente${_rows.length == 1 ? '' : 's'}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _kMuted,
                  ),
                ),
              ),
              if (!_ehLembrete)
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selecionados.length == _rows.length) {
                        _selecionados.clear();
                      } else {
                        _selecionados
                          ..clear()
                          ..addAll(_rows.map((e) => e.clienteId));
                      }
                    });
                  },
                  child: Text(
                    _selecionados.length == _rows.length
                        ? 'Limpar seleção'
                        : 'Selecionar todos',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _kRoxo,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            itemCount: _paginaAtual.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _buildClienteTile(_paginaAtual[i]),
          ),
        ),
        if (_totalPaginas > 1) _buildPaginacao(),
      ],
    );
  }

  Widget _buildClienteTile(_ClienteAcaoRow row) {
    final canais = _canaisDisponiveisPara(row);
    final selecionado = _selecionados.contains(row.clienteId);

    return Material(
      color: _kFundo,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: !_ehLembrete && _fase == _FaseModal.lista
            ? () {
                setState(() {
                  if (selecionado) {
                    _selecionados.remove(row.clienteId);
                  } else {
                    _selecionados.add(row.clienteId);
                  }
                });
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_ehLembrete && _fase == _FaseModal.lista) ...[
                Checkbox(
                  value: selecionado,
                  activeColor: _kRoxo,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selecionados.add(row.clienteId);
                      } else {
                        _selecionados.remove(row.clienteId);
                      }
                    });
                  },
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.nome,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _kTexto,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      row.parcelaLabel,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: _kMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _chipInfo(
                          Icons.payments_rounded,
                          ComercialPendenciasService.formatarMoeda(row.valor),
                          _kRoxo,
                        ),
                        _chipInfo(
                          Icons.event_rounded,
                          _dataFmt.format(row.vencimento),
                          _kLaranja,
                        ),
                        _chipInfo(
                          Icons.timer_outlined,
                          '${row.diasAtraso}d atraso',
                          const Color(0xFFDC2626),
                        ),
                      ],
                    ),
                    if (_ehLembrete || _fase != _FaseModal.lista) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: canais.isEmpty
                            ? [
                                Text(
                                  'Sem canal disponível',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    color: const Color(0xFFDC2626),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ]
                            : canais.map((c) {
                                final meta = _kCanaisMeta.firstWhere((m) => m.id == c);
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: meta.cor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(meta.icone, size: 12, color: meta.cor),
                                      const SizedBox(width: 4),
                                      Text(
                                        meta.label,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: meta.cor,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipInfo(IconData icon, String text, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cor),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _kTexto,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginacao() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _pagina > 1 ? () => setState(() => _pagina--) : null,
            icon: const Icon(Icons.chevron_left_rounded),
            color: _kRoxo,
          ),
          Text(
            'Página $_pagina de $_totalPaginas',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _kMuted,
            ),
          ),
          IconButton(
            onPressed: _pagina < _totalPaginas
                ? () => setState(() => _pagina++)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
            color: _kRoxo,
          ),
        ],
      ),
    );
  }

  Widget _buildEscolhaCanal() {
    final disponiveis = _kCanaisMeta
        .where((c) => _canaisConfigurados[c.id] == true)
        .toList();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Escolha o canal de envio',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _kTexto,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_selecionados.length} cliente(s) selecionado(s). A cobrança usará o template configurado.',
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _kMuted),
          ),
          const SizedBox(height: 20),
          if (disponiveis.isEmpty)
            Text(
              'Nenhum canal ativo nas Configurações Comerciais.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: const Color(0xFFDC2626),
                fontWeight: FontWeight.w600,
              ),
            )
          else
            ...disponiveis.map((c) {
              final sel = _canalEscolhido == c.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: sel ? c.cor.withValues(alpha: 0.08) : _kFundo,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() => _canalEscolhido = c.id),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: sel ? c.cor : const Color(0xFFE2E8F0),
                          width: sel ? 1.6 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(c.icone, color: c.cor),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              c.label,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _kTexto,
                              ),
                            ),
                          ),
                          if (sel)
                            Icon(Icons.check_circle_rounded, color: c.cor),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildProcessando() {
    final totalAlvo = _ehLembrete
        ? _rows.where((r) => _canaisDisponiveisPara(r).isNotEmpty).length
        : _selecionados.length;
    final pct = totalAlvo == 0 ? 0.0 : _progressoAtual / totalAlvo;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, _) {
              final t = 0.85 + (_pulse.value * 0.15);
              return Transform.scale(
                scale: t,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [_kRoxo, Color(0xFF8E24AA)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _kRoxo.withValues(alpha: 0.35),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 32),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          Text(
            'Enviando notificações...',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _kTexto,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$_progressoAtual de $totalAlvo',
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _kMuted),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: const Color(0xFFEDE9FE),
              valueColor: const AlwaysStoppedAnimation(_kRoxo),
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: ListView.builder(
              itemCount: _rows.where((r) => r.status != _EnvioStatus.pendente || _selecionados.contains(r.clienteId) || _ehLembrete).length,
              itemBuilder: (context, index) {
                final visiveis = _rows.where((r) {
                  if (_ehLembrete) return true;
                  return _selecionados.contains(r.clienteId);
                }).toList();
                if (index >= visiveis.length) return const SizedBox.shrink();
                final row = visiveis[index];
                return _statusLinha(row);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusLinha(_ClienteAcaoRow row) {
    final (IconData icone, Color cor, String label) = switch (row.status) {
      _EnvioStatus.enviando => (Icons.hourglass_top_rounded, _kLaranja, 'Enviando...'),
      _EnvioStatus.sucesso => (Icons.check_circle_rounded, const Color(0xFF16A34A), 'Enviado com sucesso'),
      _EnvioStatus.parcial => (Icons.warning_amber_rounded, _kLaranja, 'Parcial'),
      _EnvioStatus.falha => (Icons.error_rounded, const Color(0xFFDC2626), 'Falha no envio'),
      _EnvioStatus.pulado => (Icons.block_rounded, _kMuted, 'Não enviado'),
      _EnvioStatus.pendente => (Icons.circle_outlined, _kMuted, 'Aguardando'),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _kFundo,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icone, size: 18, color: cor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.nome,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _kTexto,
                    ),
                  ),
                  if (row.detalhe.isNotEmpty)
                    Text(
                      row.detalhe,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        color: _kMuted,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: cor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRelatorio() {
    final falhas = _rows
        .where((r) =>
            r.status == _EnvioStatus.falha ||
            r.status == _EnvioStatus.parcial ||
            r.status == _EnvioStatus.pulado)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _okCount > 0 && _failCount == 0
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFFFF7ED),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _okCount > 0 && _failCount == 0
                    ? Icons.check_rounded
                    : Icons.assessment_rounded,
                color: _okCount > 0 && _failCount == 0
                    ? const Color(0xFF16A34A)
                    : _kLaranja,
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'Relatório de envio',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _kTexto,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _kpiBox('Sucesso', '$_okCount', const Color(0xFF16A34A))),
              const SizedBox(width: 10),
              Expanded(child: _kpiBox('Falhas', '$_failCount', const Color(0xFFDC2626))),
              const SizedBox(width: 10),
              Expanded(child: _kpiBox('Não enviados', '$_skipCount', _kMuted)),
            ],
          ),
          if (falhas.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Detalhes',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _kTexto,
              ),
            ),
            const SizedBox(height: 8),
            ...falhas.map(_statusLinha),
          ],
        ],
      ),
    );
  }

  Widget _kpiBox(String label, String value, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: cor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _kMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    if (_fase == _FaseModal.processando) {
      return const SizedBox(height: 12);
    }

    String primaryLabel;
    VoidCallback? primaryAction;

    switch (_fase) {
      case _FaseModal.lista:
        if (_ehLembrete) {
          primaryLabel = 'Enviar notificações';
          primaryAction = _rows.isEmpty ? null : _iniciarEnvioLembretes;
        } else {
          primaryLabel = 'Gerar cobrança';
          primaryAction = _selecionados.isEmpty
              ? null
              : () => setState(() => _fase = _FaseModal.canal);
        }
        break;
      case _FaseModal.canal:
        primaryLabel = 'Enviar cobranças';
        primaryAction = _canalEscolhido == null ? null : _iniciarEnvioCobrancas;
        break;
      case _FaseModal.relatorio:
        primaryLabel = 'Fechar';
        primaryAction = _fechar;
        break;
      case _FaseModal.processando:
        primaryLabel = '';
        primaryAction = null;
        break;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEEEAF6))),
      ),
      child: Row(
        children: [
          if (_fase == _FaseModal.canal)
            TextButton(
              onPressed: () => setState(() {
                _fase = _FaseModal.lista;
                _canalEscolhido = null;
              }),
              child: Text(
                'Voltar',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                  color: _kMuted,
                ),
              ),
            )
          else if (_fase != _FaseModal.relatorio)
            TextButton(
              onPressed: _fechar,
              child: Text(
                'Cancelar',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                  color: _kMuted,
                ),
              ),
            ),
          const Spacer(),
          FilledButton(
            onPressed: primaryAction,
            style: FilledButton.styleFrom(
              backgroundColor: PainelAdminTheme.roxo,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              primaryLabel,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

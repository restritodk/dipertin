import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/constants/tipos_entrega.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/admin_perfil.dart';
import 'package:depertin_web/utils/loja_pausa.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:depertin_web/widgets/loja_pausa_motivo_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'configuracoes_screen.dart';

/// No [PainelShellScreen], rota `/configuracoes`: master/staff vê [ConfiguracoesScreen];
/// lojista vê [ConfiguracoesLojistaScreen].
class ConfiguracoesPainelSlot extends StatelessWidget {
  const ConfiguracoesPainelSlot({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const _CfgScaffold(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: PainelAdminTheme.roxo),
                  SizedBox(height: 16),
                  Text(
                    'Carregando configurações…',
                    style: TextStyle(
                      color: PainelAdminTheme.textoSecundario,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snap.hasData || !snap.data!.exists || snap.data!.data() == null) {
          return _CfgScaffold(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _CfgSurfaceCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_off_outlined,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Não foi possível carregar seu perfil.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: PainelAdminTheme.dashboardInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        final dados = snap.data!.data()!;
        final perfil = perfilAdministrativoPainel(dados);
        if (perfil == 'lojista') {
          if (nivelAcessoPainelLojista(dados) < 3) {
            return const _CfgScaffold(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Sua conta não tem permissão para Configurações da loja.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: PainelAdminTheme.textoSecundario,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            );
          }
          final uidLoja = uidLojaEfetivo(dados, uid);
          final docRef = FirebaseFirestore.instance
              .collection('users')
              .doc(uidLoja);
          return ConfiguracoesLojistaScreen(
            docRef: docRef,
            dadosUsuarioLogado: dados,
          );
        }
        return const ConfiguracoesScreen();
      },
    );
  }
}

class _CfgScaffold extends StatelessWidget {
  const _CfgScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      body: child,
    );
  }
}

class _CfgSurfaceCard extends StatelessWidget {
  const _CfgSurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: PainelAdminTheme.dashboardCard(),
      child: child,
    );
  }
}

/// Configurações operacionais da loja (mesmos campos principais do app mobile).
class ConfiguracoesLojistaScreen extends StatefulWidget {
  const ConfiguracoesLojistaScreen({
    super.key,
    required this.docRef,
    required this.dadosUsuarioLogado,
  });

  final DocumentReference<Map<String, dynamic>> docRef;
  final Map<String, dynamic> dadosUsuarioLogado;

  @override
  State<ConfiguracoesLojistaScreen> createState() =>
      _ConfiguracoesLojistaScreenState();
}

class _ConfiguracoesLojistaScreenState
    extends State<ConfiguracoesLojistaScreen> {
  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;

  static const _ink = PainelAdminTheme.dashboardInk;
  static const _muted = PainelAdminTheme.textoSecundario;

  final _nomeLojaC = TextEditingController();
  final _enderecoC = TextEditingController();
  final _telefoneC = TextEditingController();
  final _cidadeC = TextEditingController();
  final _ufC = TextEditingController();

  bool _pausadoManual = false;
  String? _pausaMotivo;
  Timestamp? _pausaVoltaAt;
  bool _salvando = false;
  bool _carregando = true;
  String? _erroCarregar;

  Set<String> _tiposEntregaSelecionados = <String>{};
  _AlertaIncompatWeb? _alertaIncompat;
  bool _dispensandoIncompat = false;

  final Map<String, String> _nomesDias = const {
    'segunda': 'Segunda-feira',
    'terca': 'Terça-feira',
    'quarta': 'Quarta-feira',
    'quinta': 'Quinta-feira',
    'sexta': 'Sexta-feira',
    'sabado': 'Sábado',
    'domingo': 'Domingo',
  };

  late Map<String, Map<String, dynamic>> _horarios;

  @override
  void initState() {
    super.initState();
    _horarios = _horariosPadrao();
    _carregarDoc();
  }

  Future<void> _carregarDoc() async {
    try {
      final snap = await widget.docRef.get();
      if (!mounted) return;
      if (snap.exists && snap.data() != null) {
        setState(() {
          _aplicarDados(snap.data()!);
          _carregando = false;
          _erroCarregar = null;
        });
      } else {
        setState(() {
          _carregando = false;
          _erroCarregar = 'Documento do usuário não encontrado.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _carregando = false;
          _erroCarregar = e.toString();
        });
      }
    }
  }

  Map<String, Map<String, dynamic>> _horariosPadrao() => {
        'segunda': {'ativo': true, 'abre': '08:00', 'fecha': '18:00'},
        'terca': {'ativo': true, 'abre': '08:00', 'fecha': '18:00'},
        'quarta': {'ativo': true, 'abre': '08:00', 'fecha': '18:00'},
        'quinta': {'ativo': true, 'abre': '08:00', 'fecha': '18:00'},
        'sexta': {'ativo': true, 'abre': '08:00', 'fecha': '18:00'},
        'sabado': {'ativo': true, 'abre': '08:00', 'fecha': '12:00'},
        'domingo': {'ativo': false, 'abre': '08:00', 'fecha': '12:00'},
      };

  void _aplicarDados(Map<String, dynamic> d) {
    _horarios = _horariosPadrao();
    _nomeLojaC.text = (d['loja_nome'] ?? d['nome'] ?? '').toString();
    _enderecoC.text = (d['endereco'] ?? '').toString();
    _telefoneC.text = (d['telefone'] ?? '').toString();
    _cidadeC.text = (d['cidade'] ?? '').toString();
    _ufC.text = (d['uf'] ?? '').toString();
    _pausadoManual = LojaPausa.lojaEfetivamentePausada(d);
    _pausaMotivo = _pausadoManual ? d['pausa_motivo']?.toString() : null;
    _pausaVoltaAt = _pausadoManual && d['pausa_volta_at'] is Timestamp
        ? d['pausa_volta_at'] as Timestamp
        : null;

    if (d['pausado_manualmente'] == true) {
      final patch = LojaPausa.patchSePausaAlmocoExpirada(d);
      if (patch.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          try {
            await widget.docRef.update(patch);
          } catch (_) {}
          if (mounted) {
            setState(() {
              _pausadoManual = false;
              _pausaMotivo = null;
              _pausaVoltaAt = null;
            });
          }
        });
      }
    }

    if (d['horarios'] != null && d['horarios'] is Map) {
      final hBanco = Map<String, dynamic>.from(d['horarios'] as Map);
      for (final k in _horarios.keys) {
        if (hBanco[k] != null && hBanco[k] is Map) {
          _horarios[k] = Map<String, dynamic>.from(hBanco[k] as Map);
        }
      }
    }

    _tiposEntregaSelecionados = TiposEntrega.lerDeDoc(d).toSet();
    _alertaIncompat = _AlertaIncompatWeb.deDados(d);
  }

  @override
  void dispose() {
    _nomeLojaC.dispose();
    _enderecoC.dispose();
    _telefoneC.dispose();
    _cidadeC.dispose();
    _ufC.dispose();
    super.dispose();
  }

  int _minutos(String hhmm) {
    final p = hhmm.split(':');
    if (p.length < 2) return 0;
    final h = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p[1]) ?? 0;
    return h * 60 + m;
  }

  bool _horariosOk() {
    for (final e in _horarios.entries) {
      final c = e.value;
      if (c['ativo'] != true) continue;
      final abre = c['abre']?.toString() ?? '00:00';
      final fecha = c['fecha']?.toString() ?? '00:00';
      if (_minutos(abre) >= _minutos(fecha)) return false;
    }
    return true;
  }

  String _normalizarCidade(String s) {
    final t = s.trim();
    if (t.isEmpty) return '';
    return t.split(RegExp(r'\s+')).map((w) {
      if (w.isEmpty) return '';
      if (w.length == 1) return w.toUpperCase();
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }

  String _ufNorm(String s) {
    final t = s.trim();
    if (t.isEmpty) return '';
    return t.length >= 2 ? t.substring(0, 2).toUpperCase() : t.toUpperCase();
  }

  String _subtituloCardPausa() {
    if (!_pausadoManual) {
      return 'Quando ativo, a loja pode ficar indisponível para novos pedidos, '
          'conforme as regras do ecossistema DiPertin.';
    }
    final buf = StringBuffer(PausaMotivoLoja.labelPt(_pausaMotivo));
    if (_pausaMotivo == PausaMotivoLoja.almoco && _pausaVoltaAt != null) {
      final dt = _pausaVoltaAt!.toDate();
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      buf.write(' — volta às $hh:$mm');
    }
    return buf.toString();
  }

  Future<void> _aoMudarPausa(bool valor) async {
    if (!valor) {
      setState(() {
        _pausadoManual = false;
        _pausaMotivo = null;
        _pausaVoltaAt = null;
      });
      return;
    }
    final escolha = await showLojaPausaMotivoDialog(
      context,
      accent: _roxo,
    );
    if (escolha == null || !mounted) return;
    setState(() {
      _pausadoManual = true;
      _pausaMotivo = escolha.motivo;
      _pausaVoltaAt = escolha.pausaVoltaAt;
    });
  }

  Future<void> _salvar() async {
    if (_enderecoC.text.trim().isEmpty) {
      _snack('Informe o endereço de retirada da loja.', erro: true);
      return;
    }
    if (!_horariosOk()) {
      _snack(
        'Em algum dia ativo, o horário de abertura precisa ser antes do fechamento.',
        erro: true,
      );
      return;
    }
    if (_tiposEntregaSelecionados.isEmpty) {
      _snack(
        'Selecione ao menos um tipo de entrega aceito pela sua loja.',
        erro: true,
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final tiposEntregaList =
          TiposEntrega.paraFirestore(_tiposEntregaSelecionados.toList());
      final upd = <String, dynamic>{
        'loja_nome': _nomeLojaC.text.trim(),
        'endereco': _enderecoC.text.trim(),
        'telefone': _telefoneC.text.trim(),
        'horarios': _horarios,
        'tipos_entrega_permitidos': tiposEntregaList,
        'tipos_entrega_atualizado_em': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (!_pausadoManual) {
        upd['pausado_manualmente'] = false;
        upd['pausa_motivo'] = FieldValue.delete();
        upd['pausa_volta_at'] = FieldValue.delete();
      } else {
        upd['pausado_manualmente'] = true;
        upd['pausa_motivo'] = _pausaMotivo;
        if (_pausaMotivo == PausaMotivoLoja.almoco && _pausaVoltaAt != null) {
          upd['pausa_volta_at'] = _pausaVoltaAt;
        } else {
          upd['pausa_volta_at'] = FieldValue.delete();
        }
      }

      final cid = _normalizarCidade(_cidadeC.text);
      final uf = _ufNorm(_ufC.text);
      if (cid.isNotEmpty) {
        upd['cidade'] = cid;
        upd['cidade_normalizada'] = cid;
      }
      if (uf.isNotEmpty) {
        upd['uf'] = uf;
        upd['uf_normalizado'] = uf;
      }

      await widget.docRef.update(upd);
      if (mounted) _snack('Configurações salvas.');
    } catch (e) {
      if (mounted) _snack('Erro ao salvar: $e', erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              erro ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                msg,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            erro ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _pickHora(String dia, bool abre) async {
    final cfg = _horarios[dia]!;
    final cur = (abre ? cfg['abre'] : cfg['fecha']).toString();
    final p = cur.split(':');
    final h = int.tryParse(p.isNotEmpty ? p[0] : '8') ?? 8;
    final m = int.tryParse(p.length > 1 ? p[1] : '0') ?? 0;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: h, minute: m),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _roxo),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        final hh = picked.hour.toString().padLeft(2, '0');
        final mm = picked.minute.toString().padLeft(2, '0');
        cfg[abre ? 'abre' : 'fecha'] = '$hh:$mm';
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ✦ MAIN BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return _buildPremiumLoading();
    }
    if (_erroCarregar != null) {
      return _buildPremiumError();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;
          return Stack(
            children: [
              // Ambient background glow
              Positioned(top: -200, right: -100,
                child: Container(width: 400, height: 400,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: _roxo.withValues(alpha: 0.025)))),
              Positioned(bottom: -150, left: -80,
                child: Container(width: 300, height: 300,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: _laranja.withValues(alpha: 0.02)))),
              SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(wide ? 60 : 20, 24, wide ? 60 : 20, 160),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Hero Header ──
                        _buildHeroHeader(),
                        const SizedBox(height: 32),

                        // ── Layout ──
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 7,
                                child: Column(
                                  children: [
                                    _buildPremiumCardIdentificacao(),
                                    const SizedBox(height: 24),
                                    _buildPremiumCardHorarios(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                flex: 5,
                                child: Column(
                                  children: [
                                    _buildPremiumCardStatus(),
                                    const SizedBox(height: 24),
                                    _buildPremiumCardLogistica(),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else
                          Column(
                            children: [
                              _buildPremiumCardStatus(),
                              const SizedBox(height: 24),
                              _buildPremiumCardIdentificacao(),
                              const SizedBox(height: 24),
                              _buildPremiumCardLogistica(),
                              const SizedBox(height: 24),
                              _buildPremiumCardHorarios(),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              // ── Floating Action Bar ──
              Positioned(bottom: 0, left: 0, right: 0,
                child: _buildPremiumSaveBar(wide)),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ✦ PREMIUM LOADING
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPremiumLoading() {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 4)),
                ],
              ),
              child: const SizedBox(
                width: 48, height: 48,
                child: CircularProgressIndicator(strokeWidth: 3, color: PainelAdminTheme.roxo),
              ),
            ),
            const SizedBox(height: 24),
            Text('Carregando configurações da loja…',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15, color: _muted, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            SizedBox(
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  backgroundColor: _roxo.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(_roxo),
                  minHeight: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ✦ PREMIUM ERROR
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPremiumError() {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.red.shade100),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.error_outline_rounded, size: 36, color: Colors.red.shade400),
                  ),
                  const SizedBox(height: 20),
                  Text('Erro ao carregar',
                    style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: _ink)),
                  const SizedBox(height: 10),
                  Text(_erroCarregar!, textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(fontSize: 14, color: _muted, height: 1.5)),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () { setState(() { _carregando = true; _erroCarregar = null; }); _carregarDoc(); },
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Tentar novamente'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _roxo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
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

  // ═══════════════════════════════════════════════════════════════════════
  // ✦ 1 — HERO HEADER
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildHeroHeader() {
    final online = !_pausadoManual;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _roxo,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _roxo.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top badge row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tune_rounded, size: 11, color: Colors.white),
                        const SizedBox(width: 6),
                        Text('CONFIGURAÇÕES',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9, fontWeight: FontWeight.w800,
                            letterSpacing: 1.2, color: Colors.white.withValues(alpha: 0.9))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 3, height: 3,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.3), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Text('Perfil e Operação',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.7))),
                ],
              ),
              const SizedBox(height: 20),

              // Main row: avatar + info + actions
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [_heroInfo(online), const SizedBox(height: 16), _heroActions()],
                )
              else
                Row(
                  children: [
                    Expanded(child: _heroInfo(online)),
                    const SizedBox(width: 20),
                    _heroActions(),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _heroInfo(bool online) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Avatar / Logo
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: Center(
            child: Text(
              (_nomeLojaC.text.isNotEmpty ? _nomeLojaC.text[0] : 'L').toUpperCase(),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22, fontWeight: FontWeight.w800, color: _roxo),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _nomeLojaC.text.isNotEmpty ? _nomeLojaC.text : 'Minha Loja',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white,
                  letterSpacing: -0.3, height: 1.1),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8, runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _heroBadge(online ? 'Loja Ativa' : 'Loja Pausada',
                    online ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                    online ? const Color(0xFFDCFCE7) : const Color(0xFFFFF3CD)),
                  HeroPulseDot(online: online),
                  Text('Recebendo pedidos',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroActions() {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: [
        _heroActionChip(Icons.edit_rounded, 'Editar', () {}),
        _heroActionChip(Icons.visibility_outlined, 'Visualizar', () {}),
        _heroActionChip(Icons.share_outlined, 'Compartilhar', () {}),
      ],
    );
  }

  Widget _heroBadge(String text, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6,
            decoration: BoxDecoration(color: textColor, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(text,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5, fontWeight: FontWeight.w700, color: textColor)),
        ],
      ),
    );
  }

  Widget _heroActionChip(IconData icon, String label, VoidCallback onTap) {
    return _PremiumActionButton(
      icon: icon,
      label: label,
      onTap: onTap,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ✦ 2 — IDENTIFICAÇÃO (mini-cards premium)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPremiumCardIdentificacao() {
    return _PremiumSectionCard(
      icon: Icons.storefront_rounded,
      title: 'Identificação',
      subtitle: 'Dados públicos da sua loja no DiPertin',
      child: Column(
        children: [
          _PremiumMiniField(
            icon: Icons.badge_outlined,
            label: 'Nome da loja',
            controller: _nomeLojaC,
          ),
          const SizedBox(height: 12),
          _PremiumMiniField(
            icon: Icons.location_on_outlined,
            label: 'Endereço de retirada',
            controller: _enderecoC,
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _PremiumMiniField(
                  icon: Icons.phone_outlined,
                  label: 'WhatsApp',
                  controller: _telefoneC,
                  keyboardType: TextInputType.phone,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PremiumMiniField(
                  icon: Icons.location_city_rounded,
                  label: 'Cidade',
                  controller: _cidadeC,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 90,
                child: _PremiumMiniField(
                  icon: Icons.map_rounded,
                  label: 'UF',
                  controller: _ufC,
                  maxLength: 2,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ✦ 3 — STATUS OPERACIONAL (smart card com pulsing dot)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPremiumCardStatus() {
    final online = !_pausadoManual;
    return _PremiumSectionCard(
      icon: Icons.power_settings_new_rounded,
      title: 'Status Operacional',
      subtitle: 'Controle a visibilidade da loja agora',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async => _aoMudarPausa(!_pausadoManual),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: online
                  ? const Color(0xFFF0FDF4).withValues(alpha: 0.6)
                  : const Color(0xFFFFFBEB).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: online
                    ? const Color(0xFF16A34A).withValues(alpha: 0.2)
                    : const Color(0xFFD97706).withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                // Pulsing indicator + status
                Column(
                  children: [
                    HeroPulseDot(online: online, size: 32),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            online ? '🟢 ONLINE' : '⏸ PAUSADA',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 18, fontWeight: FontWeight.w800,
                              color: online ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                              letterSpacing: 1,),
                          ),
                          const Spacer(),
                          _statusSwitch(online),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        online ? 'Sua loja está ativa e recebendo pedidos normalmente.' : _subtituloCardPausa(),
                        style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: _muted, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusSwitch(bool online) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: online
              ? const Color(0xFF16A34A).withValues(alpha: 0.25)
              : const Color(0xFFD97706).withValues(alpha: 0.25),
        ),
      ),
      child: Switch.adaptive(
        value: online,
        activeTrackColor: const Color(0xFF16A34A).withValues(alpha: 0.35),
        inactiveThumbColor: const Color(0xFFD97706),
        inactiveTrackColor: const Color(0xFFD97706).withValues(alpha: 0.25),
        onChanged: (v) async => _aoMudarPausa(!v),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ✦ 4 — HORÁRIOS (Timeline premium)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPremiumCardHorarios() {
    final hoje = DateTime.now().weekday;
    final diasMap = {1: 'segunda', 2: 'terca', 3: 'quarta', 4: 'quinta', 5: 'sexta', 6: 'sabado', 7: 'domingo'};
    final hojeChave = diasMap[hoje] ?? '';
    return _PremiumSectionCard(
      icon: Icons.calendar_today_rounded,
      title: 'Horários',
      subtitle: 'Disponibilidade semanal da loja',
      child: Column(
        children: [
          for (var i = 0; i < _horarios.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _buildPremiumTimelineDay(
              chave: _horarios.keys.elementAt(i),
              eHoje: _horarios.keys.elementAt(i) == hojeChave,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPremiumTimelineDay({required String chave, bool eHoje = false}) {
    final cfg = _horarios[chave]!;
    final ativo = cfg['ativo'] == true;
    final dia = _nomesDias[chave]!;
    final corDia = ativo ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final fundoDia = ativo ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: ativo ? Colors.white : fundoDia.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ativo
              ? const Color(0xFF16A34A).withValues(alpha: 0.2)
              : const Color(0xFFFECACA).withValues(alpha: 0.4),
          width: ativo ? 1 : 1,
        ),
        boxShadow: ativo
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))]
            : null,
      ),
      child: Row(
        children: [
          // Timeline dot
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              color: corDia, shape: BoxShape.circle,
              border: Border.all(color: corDia.withValues(alpha: 0.3), width: 2),
            ),
          ),
          const SizedBox(width: 8),
          // Dashed timeline connector
          Container(width: 16, height: 1.5,
            color: ativo ? const Color(0xFF16A34A).withValues(alpha: 0.2) : Colors.grey.shade200),
          const SizedBox(width: 8),

          // Day name
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(dia,
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: ativo ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13.5, color: ativo ? _ink : _muted)),
              if (eHoje) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _roxo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('HOJE',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 8, fontWeight: FontWeight.w800,
                      color: _roxo, letterSpacing: 0.6)),
                ),
              ],
            ],
          ),

          const Spacer(),

          // Hours or closed
          if (ativo)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPremiumTimeChip(
                  label: 'Abre', value: cfg['abre'].toString(),
                  onTap: () => _pickHora(chave, true)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: _roxo.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(Icons.arrow_forward_rounded, size: 12, color: _roxo.withValues(alpha: 0.4)),
                  ),
                ),
                _buildPremiumTimeChip(
                  label: 'Fecha', value: cfg['fecha'].toString(),
                  onTap: () => _pickHora(chave, false)),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: fundoDia,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFECACA).withValues(alpha: 0.4)),
              ),
              child: Text('Fechado',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5, fontWeight: FontWeight.w700,
                  color: const Color(0xFFDC2626))),
            ),

          // Checkbox
          const SizedBox(width: 8),
          Transform.scale(
            scale: 0.85,
            child: Checkbox(
              value: ativo,
              activeColor: _roxo,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
              side: BorderSide(color: ativo ? _roxo : Colors.grey.shade300, width: 1.2),
              onChanged: (v) => setState(() => cfg['ativo'] = v ?? false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumTimeChip({
    required String label, required String value, required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFE),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: GoogleFonts.plusJakartaSans(
                fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: _muted)),
              const SizedBox(height: 1),
              Text(value, style: GoogleFonts.plusJakartaSans(
                fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ✦ 5 — LOGÍSTICA (Premium vehicle selection cards)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPremiumCardLogistica() {
    final List<String> selecOrdenada = _tiposEntregaSelecionados.toList()
      ..sort((a, b) => (TiposEntrega.hierarquia[a] ?? 0).compareTo(TiposEntrega.hierarquia[b] ?? 0));
    final String? maior = TiposEntrega.maiorTipoDaLista(selecOrdenada);
    final alerta = _alertaIncompat;

    return _PremiumSectionCard(
      icon: Icons.local_shipping_rounded,
      title: 'Logística',
      subtitle: 'Modos de entrega e precificação',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (alerta != null && alerta.ativo) ...[
            _buildPremiumAlertaIncompat(alerta),
            const SizedBox(height: 16),
          ],
          if (maior != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_roxo.withValues(alpha: 0.06), _roxo.withValues(alpha: 0.02)],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _roxo.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _roxo.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: _roxo, size: 14),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _ink, height: 1.35),
                        children: [
                          const TextSpan(text: 'Tabela ativa: '),
                          TextSpan(
                            text: TiposEntrega.rotulo(maior),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const TextSpan(text: '. Custo base para cálculo de frete.'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Vehicle cards grid
          ...TiposEntrega.ordemCanonica.map(
            (codigo) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildPremiumVehicleCard(codigo),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumVehicleCard(String codigo) {
    final bool selecionado = _tiposEntregaSelecionados.contains(codigo);
    final IconData icone;
    final String raio;
    final String tempoMedio;
    switch (codigo) {
      case TiposEntrega.codBicicleta:
        icone = Icons.pedal_bike_rounded;
        raio = '~2 km'; tempoMedio = '~30 min';
        break;
      case TiposEntrega.codMoto:
        icone = Icons.two_wheeler_rounded;
        raio = '~15 km'; tempoMedio = '~20 min';
        break;
      case TiposEntrega.codCarro:
        icone = Icons.directions_car_rounded;
        raio = '~25 km'; tempoMedio = '~15 min';
        break;
      case TiposEntrega.codCarroFrete:
        icone = Icons.local_shipping_rounded;
        raio = '~100 km'; tempoMedio = '~30 min';
        break;
      default:
        icone = Icons.inventory_2_outlined;
        raio = '—'; tempoMedio = '—';
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (selecionado) {
              _tiposEntregaSelecionados.remove(codigo);
            } else {
              _tiposEntregaSelecionados.add(codigo);
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selecionado ? _laranja.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selecionado ? _laranja : Colors.grey.shade200,
              width: selecionado ? 1.5 : 1,
            ),
            boxShadow: selecionado
                ? [
                    BoxShadow(
                      color: _laranja.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: selecionado ? _laranja.withValues(alpha: 0.15) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icone, color: selecionado ? _laranja : _muted, size: 28),
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(TiposEntrega.rotulo(codigo),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            selecionado ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            key: ValueKey(selecionado),
                            size: 22, color: selecionado ? _laranja : _muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(TiposEntrega.descricaoCurta(codigo),
                      style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: _muted, height: 1.3)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _roxo.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.radar_rounded, size: 11, color: _roxo.withValues(alpha: 0.5)),
                          const SizedBox(width: 4),
                          Text('Raio $raio',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10.5, color: _muted, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 10),
                          Icon(Icons.timer_outlined, size: 11, color: _roxo.withValues(alpha: 0.5)),
                          const SizedBox(width: 4),
                          Text(tempoMedio,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10.5, color: _muted, fontWeight: FontWeight.w600)),
                        ],
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
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ✦ ALERTA DE INCOMPATIBILIDADE (premium)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPremiumAlertaIncompat(_AlertaIncompatWeb a) {
    final ultimo = a.ultimoEm;
    final ultimoTxt = ultimo == null ? '' : ' (último em ${_fmtDataHora(ultimo)})';
    final tiposAceitos = a.ultimoTiposAceitosLoja.map(TiposEntrega.rotulo).join(', ');
    final tipoEntreg = a.ultimoTipoEntregador.isEmpty
        ? 'não informado'
        : TiposEntrega.rotulo(a.ultimoTipoEntregador);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.shade50, Colors.orange.shade50.withValues(alpha: 0.4)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.pedal_bike_rounded, color: Colors.amber.shade800, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Cancelamentos por incompatibilidade',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.amber.shade900)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Entregadores já reportaram ${a.totalUltimos30d} cancelamento(s) '
            'desta loja marcando "produto incompatível com meu veículo"$ultimoTxt.',
            style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: Colors.amber.shade900, height: 1.45),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Veículo: $tipoEntreg',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Colors.amber.shade900)),
                    ),
                    if (tiposAceitos.isNotEmpty)
                      Text('Sua loja aceita: $tiposAceitos',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Colors.amber.shade900)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _dispensandoIncompat ? null : _dispensarAlertaIncompat,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.amber.shade800,
                side: BorderSide(color: Colors.amber.shade400),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: _dispensandoIncompat
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_rounded, size: 16),
              label: Text(_dispensandoIncompat ? 'Dispensando…' : 'Já revisei',
                style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ✦ FLOATING ACTION BAR (Save Bar)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPremiumSaveBar(bool wide) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(horizontal: wide ? 60 : 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: Colors.grey.shade200, width: 0.5)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, -4)),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _laranja.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.info_outline_rounded, size: 20, color: _laranja),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Alterações não salvas podem ser perdidas. Salve para aplicar na vitrine.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _muted, height: 1.3),
                ),
              ),
              const SizedBox(width: 20),
              _buildPremiumSaveButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumSaveButton() {
    final isSaving = _salvando;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: isSaving ? null : _salvar,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_roxo, Color(0xFF8E24AA)],
              begin: Alignment.centerLeft, end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _roxo.withValues(alpha: isSaving ? 0.15 : 0.3),
                blurRadius: isSaving ? 8 : 16,
                offset: Offset(0, isSaving ? 2 : 5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              isSaving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 20, color: Colors.white),
              const SizedBox(width: 10),
              Text(isSaving ? 'Salvando…' : 'Salvar alterações',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  /// Grava `alerta_tipos_entrega_incompat.dispensado_em = now` no doc do
  /// usuário logado. Só esconde o alerta — preserva o histórico.
  Future<void> _dispensarAlertaIncompat() async {
    if (_dispensandoIncompat) return;
    setState(() => _dispensandoIncompat = true);
    try {
      await widget.docRef.set({
        'alerta_tipos_entrega_incompat': {
          'dispensado_em': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
      if (!mounted) return;
      final snap = await widget.docRef.get();
      if (!mounted) return;
      setState(() {
        if (snap.data() != null) {
          _alertaIncompat = _AlertaIncompatWeb.deDados(snap.data()!);
        }
        _dispensandoIncompat = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Alerta dispensado. Reaparece se houver novo caso.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF16A34A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _dispensandoIncompat = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Falha ao dispensar: $e',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFDC2626),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
    }
  }

  String _fmtDataHora(DateTime dt) {
    String d2(int n) => n.toString().padLeft(2, '0');
    return '${d2(dt.day)}/${d2(dt.month)} ${d2(dt.hour)}:${d2(dt.minute)}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ★ PREMIUM REUSABLE COMPONENTS
// ═══════════════════════════════════════════════════════════════════════════

/// Premium action button with purple gradient and hover effect
class _PremiumActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PremiumActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_PremiumActionButton> createState() => _PremiumActionButtonState();
}

class _PremiumActionButtonState extends State<_PremiumActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _hovered
                  ? [const Color(0xFFE67E00), const Color(0xFFFF9F00)]
                  : [laranja_, const Color(0xFFFFA726)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: laranja_.withValues(alpha: _hovered ? 0.4 : 0.3),
                blurRadius: _hovered ? 14 : 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16, color: const Color(0xFF1A1A2E)),
              const SizedBox(width: 8),
              Text(widget.label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A2E))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Premium card wrapper with consistent styling
class _PremiumSectionCard extends StatelessWidget {
  const _PremiumSectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [roxo_.withValues(alpha: 0.1), roxo_.withValues(alpha: 0.04)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: roxo_, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16, fontWeight: FontWeight.w700, color: ink_, letterSpacing: -0.2)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                        style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: muted_, height: 1.3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: Colors.grey.shade100),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: child,
          ),
        ],
      ),
    );
  }
}

const Color roxo_ = Color(0xFF6A1B9A);
const Color laranja_ = Color(0xFFFF8F00);
const Color ink_ = Color(0xFF1A1A2E);
const Color muted_ = Color(0xFF64748B);

/// Premium mini card for form fields
class _PremiumMiniField extends StatelessWidget {
  final IconData icon;
  final String label;
  final TextEditingController controller;
  final int? maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextAlign textAlign;
  final TextCapitalization textCapitalization;

  const _PremiumMiniField({
    required this.icon,
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.textAlign = TextAlign.start,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        maxLength: maxLength,
        keyboardType: keyboardType,
        textAlign: textAlign,
        textCapitalization: textCapitalization,
        style: GoogleFonts.plusJakartaSans(fontSize: 14, color: ink_, height: 1.3),
        decoration: InputDecoration(
          labelText: label,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          prefixIcon: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 17, color: roxo_.withValues(alpha: 0.4)),
          ),
          border: InputBorder.none,
          labelStyle: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: roxo_.withValues(alpha: 0.6), fontWeight: FontWeight.w600),
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

/// Animated pulsing dot for status indication
class HeroPulseDot extends StatefulWidget {
  final bool online;
  final double size;
  const HeroPulseDot({super.key, this.online = true, this.size = 10});

  @override
  State<HeroPulseDot> createState() => _HeroPulseDotState();
}

class _HeroPulseDotState extends State<HeroPulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final cor = widget.online ? const Color(0xFF16A34A) : const Color(0xFFD97706);
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: cor.withValues(alpha: _animation.value),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: cor.withValues(alpha: _animation.value * 0.3),
                blurRadius: widget.size * 0.6,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Snapshot imutável do campo `alerta_tipos_entrega_incompat` persistido no
/// doc do lojista. Espelha a classe `_AlertaIncompat` do app mobile.
class _AlertaIncompatWeb {
  _AlertaIncompatWeb({
    required this.totalUltimos30d,
    required this.ultimoEm,
    required this.dispensadoEm,
    required this.ultimoPedidoId,
    required this.ultimoTipoEntregador,
    required this.ultimoTiposAceitosLoja,
  });

  final int totalUltimos30d;
  final DateTime? ultimoEm;
  final DateTime? dispensadoEm;
  final String ultimoPedidoId;
  final String ultimoTipoEntregador;
  final List<String> ultimoTiposAceitosLoja;

  bool get ativo {
    if (totalUltimos30d <= 0) return false;
    if (ultimoEm == null) return false;
    if (dispensadoEm == null) return true;
    return ultimoEm!.isAfter(dispensadoEm!);
  }

  static _AlertaIncompatWeb? deDados(Map<String, dynamic>? d) {
    if (d == null) return null;
    final raw = d['alerta_tipos_entrega_incompat'];
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    DateTime? ts(dynamic v) =>
        v is Timestamp ? v.toDate() : (v is DateTime ? v : null);
    final aceitos = (m['ultimo_tipos_aceitos_loja'] is Iterable)
        ? List<String>.from(
            (m['ultimo_tipos_aceitos_loja'] as Iterable)
                .map((e) => e?.toString() ?? '')
                .where((s) => s.isNotEmpty),
          )
        : <String>[];
    return _AlertaIncompatWeb(
      totalUltimos30d: (m['total_ultimos_30d'] is num)
          ? (m['total_ultimos_30d'] as num).toInt()
          : 0,
      ultimoEm: ts(m['ultimo_em']),
      dispensadoEm: ts(m['dispensado_em']),
      ultimoPedidoId: m['ultimo_pedido_id']?.toString() ?? '',
      ultimoTipoEntregador: m['ultimo_tipo_entregador']?.toString() ?? '',
      ultimoTiposAceitosLoja: aceitos,
    );
  }
}

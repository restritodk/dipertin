import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/admin_perfil.dart';
import 'package:depertin_web/utils/loja_pausa.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
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

class _ConfiguracoesLojistaScreenState extends State<ConfiguracoesLojistaScreen> {
  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;

  static const _ink = PainelAdminTheme.dashboardInk;
  static const _muted = PainelAdminTheme.textoSecundario;
  static const _surfaceMuted = Color(0xFFF8FAFC);
  static const _borderLight = Color(0xFFE2E8F0);

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

    setState(() => _salvando = true);
    try {
      final upd = <String, dynamic>{
        'loja_nome': _nomeLojaC.text.trim(),
        'endereco': _enderecoC.text.trim(),
        'telefone': _telefoneC.text.trim(),
        'horarios': _horarios,
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
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: erro ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
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

  InputDecoration _dec(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon != null
          ? Icon(icon, size: 20, color: _muted)
          : null,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _roxo, width: 1.5),
      ),
      labelStyle: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        color: _muted,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
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
    if (_erroCarregar != null) {
      return Scaffold(
        backgroundColor: PainelAdminTheme.fundoCanvas,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _CfgSurfaceCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 44, color: Colors.red.shade400),
                    const SizedBox(height: 12),
                    Text(
                      _erroCarregar!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        color: _ink,
                        height: 1.4,
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

    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      floatingActionButton: const BotaoSuporteFlutuante(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final horariosEmLinha = constraints.maxWidth >= 720;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              wide ? 40 : 20,
              28,
              wide ? 40 : 20,
              120,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 28),
                    _buildCardIdentificacao(wide),
                    const SizedBox(height: 16),
                    _buildCardPausa(),
                    const SizedBox(height: 16),
                    _buildCardHorarios(horariosEmLinha),
                    const SizedBox(height: 32),
                    _buildSaveButton(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CONFIGURAÇÕES DA LOJA',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
            color: _muted,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Dados e horários',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: _ink,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Informações operacionais visíveis aos clientes na vitrine. '
          'Alterações aplicam-se conforme as regras do aplicativo.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: _muted,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildCardIdentificacao(bool wide) {
    return Container(
      decoration: PainelAdminTheme.dashboardCard(),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(
            icon: Icons.storefront_outlined,
            title: 'Identificação e contato',
            subtitle: 'Nome, local e forma de contato da loja',
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _nomeLojaC,
            decoration: _dec('Nome da loja', icon: Icons.badge_outlined),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _enderecoC,
            maxLines: 2,
            decoration: _dec(
              'Endereço de retirada / atendimento',
              icon: Icons.location_on_outlined,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _telefoneC,
            keyboardType: TextInputType.phone,
            decoration: _dec('Telefone / WhatsApp', icon: Icons.phone_outlined),
          ),
          const SizedBox(height: 16),
          wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _cidadeC,
                        decoration: _dec('Cidade', icon: Icons.location_city_outlined),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _ufC,
                        maxLength: 2,
                        textCapitalization: TextCapitalization.characters,
                        decoration: _dec('UF'),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    TextField(
                      controller: _cidadeC,
                      decoration: _dec('Cidade', icon: Icons.location_city_outlined),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _ufC,
                      maxLength: 2,
                      textCapitalization: TextCapitalization.characters,
                      decoration: _dec('UF'),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildCardPausa() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _pausadoManual
              ? const Color(0xFFF59E0B).withValues(alpha: 0.55)
              : _borderLight,
          width: _pausadoManual ? 1.5 : 1,
        ),
        boxShadow: PainelAdminTheme.sombraCardSuave(),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        secondary: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _pausadoManual
                ? const Color(0xFFFFFBEB)
                : _surfaceMuted,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _pausadoManual ? Icons.pause_circle_filled_rounded : Icons.play_circle_outline_rounded,
            color: _pausadoManual ? const Color(0xFFD97706) : _muted,
            size: 26,
          ),
        ),
        title: Text(
          'Pausar pedidos manualmente',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: _ink,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _subtituloCardPausa(),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              height: 1.45,
              color: _muted,
            ),
          ),
        ),
        value: _pausadoManual,
        activeThumbColor: _laranja,
        activeTrackColor: _laranja.withValues(alpha: 0.45),
        onChanged: (v) async => _aoMudarPausa(v),
      ),
    );
  }

  Widget _buildCardHorarios(bool emLinha) {
    return Container(
      decoration: PainelAdminTheme.dashboardCard(),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(
            icon: Icons.schedule_rounded,
            title: 'Horário de funcionamento',
            subtitle: 'Marque os dias úteis e defina abertura e encerramento',
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: _surfaceMuted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderLight),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _horarios.length; i++) ...[
                  if (i > 0) const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
                  _linhaHorario(_horarios.keys.elementAt(i), emLinha),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _roxo.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _roxo, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _muted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return FilledButton.icon(
      onPressed: _salvando ? null : _salvar,
      style: FilledButton.styleFrom(
        backgroundColor: _laranja,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
      ),
      icon: _salvando
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.save_rounded, size: 22),
      label: Text(
        _salvando ? 'Salvando…' : 'Salvar alterações',
        style: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _linhaHorario(String chave, bool emLinha) {
    final cfg = _horarios[chave]!;
    final ativo = cfg['ativo'] == true;
    final dia = _nomesDias[chave]!;

    Widget horasWidget() {
      if (!ativo) {
        return Align(
          alignment: emLinha ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Encerrado',
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFFB91C1C),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        );
      }
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _timeChip(
            label: 'Abre',
            value: cfg['abre'].toString(),
            onTap: () => _pickHora(chave, true),
          ),
          Icon(Icons.arrow_forward_rounded, size: 18, color: _muted.withValues(alpha: 0.7)),
          _timeChip(
            label: 'Fecha',
            value: cfg['fecha'].toString(),
            onTap: () => _pickHora(chave, false),
          ),
        ],
      );
    }

    final check = SizedBox(
      width: 42,
      child: Checkbox(
        value: ativo,
        activeColor: _roxo,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        onChanged: (v) => setState(() => cfg['ativo'] = v ?? false),
      ),
    );

    final tituloDia = Text(
      dia,
      style: GoogleFonts.plusJakartaSans(
        fontWeight: ativo ? FontWeight.w700 : FontWeight.w600,
        fontSize: 14,
        color: ativo ? _ink : _muted,
      ),
    );

    if (emLinha) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            check,
            Expanded(flex: 2, child: tituloDia),
            if (ativo)
              Flexible(flex: 3, child: horasWidget())
            else
              Expanded(child: horasWidget()),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              check,
              Expanded(child: tituloDia),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 42, top: 10),
            child: horasWidget(),
          ),
        ],
      ),
    );
  }

  Widget _timeChip({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: _muted,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

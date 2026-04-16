import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:depertin_cliente/services/android_nav_intent.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _roxoClaro = Color(0xFF9C4DCC);
const Color _laranja = Color(0xFFFF8F00);
const Color _verde = Color(0xFF2E7D32);
const Color _bg = Color(0xFFF5F5FA);

class DiagnosticoAlertasCorridaScreen extends StatefulWidget {
  const DiagnosticoAlertasCorridaScreen({super.key});

  @override
  State<DiagnosticoAlertasCorridaScreen> createState() =>
      _DiagnosticoAlertasCorridaScreenState();
}

class _DiagnosticoAlertasCorridaScreenState
    extends State<DiagnosticoAlertasCorridaScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _loading = true;
  int _sdk = 0;
  String _manufacturer = '';
  String _brand = '';
  String _model = '';
  bool _notifRuntimeGranted = true;
  bool _notifSystemEnabled = true;
  bool _fullScreenAllowed = true;
  bool _batteryUnrestricted = true;
  bool _overlayAllowed = true;
  bool _autostartAtivo = false;

  AnimationController? _scoreAnim;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  bool get _isAndroid14Plus => _sdk >= 34;
  bool get _temAutostart => _oemTemAutostart();

  int get _totalChecks {
    int c = 4; // notifRuntime, notifSystem, battery, overlay
    if (_isAndroid14Plus) c++;
    return c;
  }

  int get _okCount {
    int c = 0;
    if (_notifRuntimeGranted) c++;
    if (_notifSystemEnabled) c++;
    if (!_isAndroid14Plus || _fullScreenAllowed) c++;
    if (_batteryUnrestricted) c++;
    if (_overlayAllowed) c++;
    return c;
  }

  double get _score => _totalChecks == 0 ? 1.0 : _okCount / _totalChecks;
  bool get _tudoOk => _okCount == _totalChecks;
  bool get _temPendencias => !_tudoOk;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scoreAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    unawaited(_carregarPreferenciaAutostart());
    _carregar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scoreAnim?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _carregar();
  }

  Future<void> _carregar() async {
    if (!_isAndroid) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);

    final info = await AndroidNavIntent.getDeviceInfo();
    final sdk = info['sdk'] as int? ?? 0;

    final results = await Future.wait([
      sdk < 33
          ? Future.value(true)
          : Permission.notification.status.then((s) => s.isGranted),
      AndroidNavIntent.areNotificationsEnabled(),
      AndroidNavIntent.canUseFullScreenIntent(),
      AndroidNavIntent.isIgnoringBatteryOptimizations(),
      AndroidNavIntent.canDrawOverlays(),
    ]);

    if (!mounted) return;
    setState(() {
      _sdk = sdk;
      _manufacturer = (info['manufacturer'] as String?) ?? '';
      _brand = (info['brand'] as String?) ?? '';
      _model = (info['model'] as String?) ?? '';
      _notifRuntimeGranted = results[0];
      _notifSystemEnabled = results[1];
      _fullScreenAllowed = results[2];
      _batteryUnrestricted = results[3];
      _overlayAllowed = results[4];
      _loading = false;
    });
    _scoreAnim?.forward(from: 0);
  }

  // ── ações ──────────────────────────────────────────────────────────

  Future<void> _solicitarPermissaoNotificacao() async {
    await Permission.notification.request();
    await _carregar();
  }

  Future<void> _abrirNotifSettings() async {
    final abriu = await AndroidNavIntent.openNotificationSettings();
    if (!abriu) await openAppSettings();
  }

  Future<void> _abrirFullScreenSettings() =>
      AndroidNavIntent.openFullScreenIntentSettings();

  Future<void> _abrirBateriaSettings() =>
      AndroidNavIntent.openBatteryOptimizationSettings();

  Future<void> _abrirOemBateriaSettings() =>
      AndroidNavIntent.openOemBatterySettings();

  Future<void> _abrirOverlaySettings() =>
      AndroidNavIntent.openOverlayPermissionSettings();

  Future<void> _abrirAutostartSettings() =>
      AndroidNavIntent.openAutostartSettings();

  Future<void> _carregarPreferenciaAutostart() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _autostartAtivo = prefs.getBool('diag_autostart_ativo') ?? false;
    });
  }

  Future<void> _marcarAutostartAtivo(bool ativo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('diag_autostart_ativo', ativo);
    if (!mounted) return;
    setState(() => _autostartAtivo = ativo);
  }

  Future<void> _acaoAutostart() async {
    await _abrirAutostartSettings();
    await _marcarAutostartAtivo(!_autostartAtivo);
  }

  Future<void> _corrigirTudo() async {
    if (!_isAndroid || !_temPendencias) return;
    if (!_notifRuntimeGranted) {
      await _solicitarPermissaoNotificacao();
      if (!mounted) return;
    }
    if (!_notifSystemEnabled) {
      await _abrirNotifSettings();
      if (!mounted) return;
    }
    if (_isAndroid14Plus && !_fullScreenAllowed) {
      await _abrirFullScreenSettings();
      if (!mounted) return;
    }
    if (!_batteryUnrestricted) {
      await _abrirBateriaSettings();
      if (!mounted) return;
    }
    if (!_overlayAllowed) {
      await _abrirOverlaySettings();
      if (!mounted) return;
    }
    await _carregar();
  }

  // ── OEM helpers ────────────────────────────────────────────────────

  bool _oemTemAutostart() {
    final m = _manufacturer.toLowerCase();
    final b = _brand.toLowerCase();
    return m.contains('xiaomi') || m.contains('redmi') || b.contains('poco') ||
        m.contains('oppo') || m.contains('oneplus') ||
        m.contains('realme') || b.contains('realme') ||
        m.contains('vivo') || b.contains('iqoo') ||
        m.contains('huawei') || m.contains('honor') ||
        m.contains('asus') || m.contains('lenovo') ||
        m.contains('meizu') || m.contains('letv') || m.contains('leeco') ||
        m.contains('infinix') || m.contains('tecno');
  }

  bool _oemTemBateriaProprietaria() {
    final m = _manufacturer.toLowerCase();
    final b = _brand.toLowerCase();
    return m.contains('xiaomi') || m.contains('redmi') || b.contains('poco') ||
        m.contains('samsung') || m.contains('huawei') || m.contains('honor') ||
        m.contains('oppo') || m.contains('oneplus') ||
        m.contains('realme') || b.contains('realme') ||
        m.contains('vivo') || b.contains('iqoo') ||
        m.contains('infinix') || m.contains('tecno');
  }

  String _nomeOem() {
    final m = _manufacturer.toLowerCase();
    final b = _brand.toLowerCase();
    if (m.contains('xiaomi') || m.contains('redmi') || b.contains('poco')) return 'Xiaomi (MIUI / HyperOS)';
    if (m.contains('samsung')) return 'Samsung (One UI)';
    if (m.contains('oppo')) return 'Oppo (ColorOS)';
    if (m.contains('oneplus')) return 'OnePlus (OxygenOS)';
    if (m.contains('realme') || b.contains('realme')) return 'Realme (Realme UI)';
    if (m.contains('vivo') || b.contains('iqoo')) return 'Vivo (Funtouch / OriginOS)';
    if (m.contains('huawei')) return 'Huawei (EMUI)';
    if (m.contains('honor')) return 'Honor (MagicUI)';
    if (m.contains('asus')) return 'Asus (ZenUI)';
    if (m.contains('meizu')) return 'Meizu (Flyme)';
    if (m.contains('infinix') || m.contains('tecno')) return 'Transsion (HiOS)';
    if (m.contains('lenovo') || m.contains('motorola')) return 'Lenovo / Motorola';
    return _manufacturer;
  }

  List<_DicaOem> _dicasOem() {
    final m = _manufacturer.toLowerCase();
    final b = _brand.toLowerCase();
    final dicas = <_DicaOem>[];

    if (m.contains('xiaomi') || m.contains('redmi') || b.contains('poco')) {
      dicas.addAll([
        _DicaOem('Habilite "Inicialização automática" (Autostart) para o DiPertin.', acao: _abrirAutostartSettings),
        _DicaOem('Em "Economia de bateria", coloque o DiPertin como "Sem restrições".', acao: _abrirOemBateriaSettings),
        _DicaOem('Permita exibir notificações na tela de bloqueio.', acao: _abrirNotifSettings),
        if (b.contains('poco') || m.contains('redmi'))
          _DicaOem('HyperOS: Apps → Gerenciar apps → DiPertin → Autostart + Background.', acao: _abrirAutostartSettings),
      ]);
    } else if (m.contains('samsung')) {
      dicas.addAll([
        _DicaOem('Device Care → Bateria → coloque DiPertin como "Nunca em modo de espera".', acao: _abrirOemBateriaSettings),
        _DicaOem('Desative "Colocar apps não utilizados em suspensão".', acao: _abrirOemBateriaSettings),
        _DicaOem('Permita "Apps que podem usar dados em segundo plano".'),
      ]);
    } else if (m.contains('oppo') || m.contains('oneplus') || m.contains('realme') || b.contains('realme')) {
      dicas.addAll([
        _DicaOem('Ative o Autostart para o DiPertin.', acao: _abrirAutostartSettings),
        _DicaOem('Desative "Otimização inteligente de energia" para o DiPertin.', acao: _abrirOemBateriaSettings),
        _DicaOem('Permita notificações de prioridade alta.', acao: _abrirNotifSettings),
      ]);
    } else if (m.contains('vivo') || b.contains('iqoo')) {
      dicas.addAll([
        _DicaOem('Ative Auto-start para o DiPertin.', acao: _abrirAutostartSettings),
        _DicaOem('Libere o app no "Gerenciador de energia".', acao: _abrirOemBateriaSettings),
        _DicaOem('Permita alertas na tela bloqueada.', acao: _abrirNotifSettings),
      ]);
    } else if (m.contains('huawei') || m.contains('honor')) {
      dicas.addAll([
        _DicaOem('Ative a Inicialização automática para o DiPertin.', acao: _abrirAutostartSettings),
        _DicaOem('Em "Gerenciamento de bateria", coloque como "Não otimizar".', acao: _abrirOemBateriaSettings),
        _DicaOem('Permita "Execução em segundo plano".', acao: _abrirOemBateriaSettings),
      ]);
    } else if (m.contains('asus')) {
      dicas.addAll([
        _DicaOem('Mobile Manager → Autostart → Ative o DiPertin.', acao: _abrirAutostartSettings),
        _DicaOem('Desative "Boost automático" que mata apps em background.'),
      ]);
    } else if (m.contains('infinix') || m.contains('tecno')) {
      dicas.addAll([
        _DicaOem('Phone Manager → Autostart → Ative o DiPertin.', acao: _abrirAutostartSettings),
        _DicaOem('Desative economia de energia para o app.', acao: _abrirOemBateriaSettings),
      ]);
    } else if (m.contains('meizu')) {
      dicas.addAll([
        _DicaOem('Segurança → Permissões → Ative autostart.', acao: _abrirAutostartSettings),
      ]);
    } else {
      dicas.addAll([
        _DicaOem('Confirme notificações ativas na tela bloqueada.', acao: _abrirNotifSettings),
        _DicaOem('Remova restrições de bateria do app.', acao: _abrirBateriaSettings),
      ]);
    }
    return dicas;
  }

  // ── build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _roxo))
          : !_isAndroid
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Diagnóstico disponível apenas no Android.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    _buildHeader(),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          if (_temPendencias) ...[
                            _buildCorrigirTudoBtn(),
                            const SizedBox(height: 16),
                          ],
                          _buildSectionTitle('Permissões do sistema'),
                          const SizedBox(height: 10),
                          _buildPermissionTile(
                            icon: Icons.notifications_active,
                            titulo: 'Notificações',
                            ok: _notifRuntimeGranted,
                            descOk: 'Permissão concedida',
                            descFail: 'Necessário para receber alertas de corrida',
                            onFix: _solicitarPermissaoNotificacao,
                          ),
                          _buildPermissionTile(
                            icon: Icons.notification_important,
                            titulo: 'Notificações no sistema',
                            ok: _notifSystemEnabled,
                            descOk: 'Ativas no sistema',
                            descFail: 'Desativadas — alertas não aparecerão',
                            onFix: _abrirNotifSettings,
                          ),
                          if (_isAndroid14Plus)
                            _buildPermissionTile(
                              icon: Icons.fullscreen,
                              titulo: 'Tela cheia (Android 14+)',
                              ok: _fullScreenAllowed,
                              descOk: 'Permitida',
                              descFail: 'Bloqueada pelo sistema',
                              onFix: _abrirFullScreenSettings,
                            ),
                          _buildPermissionTile(
                            icon: Icons.battery_saver,
                            titulo: 'Otimização de bateria',
                            ok: _batteryUnrestricted,
                            descOk: 'Sem restrição',
                            descFail: 'Pode impedir alertas em segundo plano',
                            onFix: _abrirBateriaSettings,
                            onFixSecundario: _oemTemBateriaProprietaria()
                                ? _abrirOemBateriaSettings
                                : null,
                            labelSecundario: 'OEM',
                          ),
                          _buildPermissionTile(
                            icon: Icons.layers,
                            titulo: 'Exibir sobre outros apps',
                            ok: _overlayAllowed,
                            descOk: 'Permitida',
                            descFail: 'Necessária para o alerta flutuante',
                            onFix: _abrirOverlaySettings,
                          ),
                          if (_temAutostart) ...[
                            const SizedBox(height: 20),
                            _buildSectionTitle('Inicialização automática'),
                            const SizedBox(height: 10),
                            _buildAutostartCard(),
                          ],
                          const SizedBox(height: 20),
                          _buildSectionTitle('Recomendações ${_nomeOem()}'),
                          const SizedBox(height: 10),
                          _buildOemChecklist(),
                          const SizedBox(height: 20),
                          _buildDeviceInfo(),
                          const SizedBox(height: 16),
                          Text(
                            'Mesmo com tudo configurado, algumas versões do Android '
                            'podem restringir alertas em segundo plano. O app usará '
                            'notificação heads-up como alternativa.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                              height: 1.5,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
    );
  }

  // ── header com score ───────────────────────────────────────────────

  Widget _buildHeader() {
    return SliverAppBar(
      expandedHeight: 230,
      pinned: true,
      backgroundColor: _roxo,
      foregroundColor: Colors.white,
      title: const Text(
        'Diagnóstico',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      actions: [
        IconButton(
          tooltip: 'Atualizar',
          onPressed: _loading ? null : _carregar,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7B1FA2), Color(0xFF4A148C)],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AnimatedBuilder(
                  animation: _scoreAnim!,
                  builder: (context, child) => _ScoreRing(
                    score: _score * (_scoreAnim?.value ?? 1.0),
                    okCount: _okCount,
                    total: _totalChecks,
                    tudoOk: _tudoOk,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _tudoOk
                      ? 'Tudo configurado!'
                      : '$_okCount de $_totalChecks permissões ativas',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withAlpha(220),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── botão corrigir tudo ────────────────────────────────────────────

  Widget _buildCorrigirTudoBtn() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_roxo, _roxoClaro],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: _roxo.withAlpha(60),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _corrigirTudo,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_fix_high,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Corrigir tudo automaticamente',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── section title ──────────────────────────────────────────────────

  Widget _buildSectionTitle(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: Colors.grey[500],
        letterSpacing: 1.2,
      ),
    );
  }

  // ── permission tile ────────────────────────────────────────────────

  Widget _buildPermissionTile({
    required IconData icon,
    required String titulo,
    required bool ok,
    required String descOk,
    required String descFail,
    Future<void> Function()? onFix,
    Future<void> Function()? onFixSecundario,
    String? labelSecundario,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ok ? _verde.withAlpha(40) : _laranja.withAlpha(60),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: ok ? _verde.withAlpha(20) : _laranja.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: ok ? _verde : _laranja, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    ok ? descOk : descFail,
                    style: TextStyle(
                      fontSize: 12,
                      color: ok ? _verde : Colors.grey[600],
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (ok)
              const Icon(Icons.check_circle_rounded, color: _verde, size: 24)
            else ...[
              if (onFixSecundario != null)
                _miniActionBtn(
                  labelSecundario ?? 'OEM',
                  onFixSecundario,
                  outlined: true,
                ),
              if (onFixSecundario != null) const SizedBox(width: 6),
              _miniActionBtn('Ativar', onFix!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniActionBtn(
    String label,
    Future<void> Function() onTap, {
    bool outlined = false,
  }) {
    return SizedBox(
      height: 32,
      child: outlined
          ? OutlinedButton(
              onPressed: () async {
                await onTap();
                await _carregar();
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                side: BorderSide(color: _roxo.withAlpha(80)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              child: Text(label),
            )
          : FilledButton(
              onPressed: () async {
                await onTap();
                await _carregar();
              },
              style: FilledButton.styleFrom(
                backgroundColor: _roxo,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              child: Text(label),
            ),
    );
  }

  // ── autostart card ─────────────────────────────────────────────────

  Widget _buildAutostartCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _laranja.withAlpha(50)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_laranja.withAlpha(30), _laranja.withAlpha(15)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.rocket_launch_rounded,
                color: _laranja, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Autostart',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_nomeOem()} pode encerrar o app em segundo plano. '
                  'Ative para garantir os alertas.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _miniActionBtn(_autostartAtivo ? 'Desativar' : 'Ativar', _acaoAutostart),
        ],
      ),
    );
  }

  // ── OEM checklist ──────────────────────────────────────────────────

  Widget _buildOemChecklist() {
    final dicas = _dicasOem();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < dicas.length; i++) ...[
            if (i > 0)
              Divider(height: 20, color: Colors.grey.withAlpha(30)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: _roxo.withAlpha(15),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _roxo,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dicas[i].texto,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[800],
                          height: 1.4,
                        ),
                      ),
                      if (dicas[i].acao != null) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () async {
                            await dicas[i].acao!();
                            await _carregar();
                          },
                          child: const Text(
                            'Abrir configuração →',
                            style: TextStyle(
                              color: _roxo,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── device info ────────────────────────────────────────────────────

  Widget _buildDeviceInfo() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.phone_android, size: 18, color: Colors.grey[500]),
              const SizedBox(width: 8),
              Text(
                'Dispositivo',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow('Modelo', '$_manufacturer $_model'),
          _infoRow('Marca', _brand),
          _infoRow('Android SDK', '$_sdk'),
          if (_nomeOem().isNotEmpty)
            _infoRow('Sistema', _nomeOem()),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── score ring ─────────────────────────────────────────────────────

class _ScoreRing extends StatelessWidget {
  final double score;
  final int okCount;
  final int total;
  final bool tudoOk;

  const _ScoreRing({
    required this.score,
    required this.okCount,
    required this.total,
    required this.tudoOk,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      height: 90,
      child: CustomPaint(
        painter: _RingPainter(score: score, tudoOk: tudoOk),
        child: Center(
          child: tudoOk
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 36)
              : Text(
                  '$okCount/$total',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double score;
  final bool tudoOk;
  _RingPainter({required this.score, required this.tudoOk});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    const strokeWidth = 6.0;

    final bgPaint = Paint()
      ..color = Colors.white.withAlpha(30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..color = tudoOk ? const Color(0xFF66BB6A) : _laranja
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * math.pi * score;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.score != score || old.tudoOk != tudoOk;
}

class _DicaOem {
  final String texto;
  final Future<void> Function()? acao;
  const _DicaOem(this.texto, {this.acao});
}

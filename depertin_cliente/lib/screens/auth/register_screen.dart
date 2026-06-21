// Arquivo: lib/screens/auth/register_screen.dart

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_multi_formatter/flutter_multi_formatter.dart';
import 'package:provider/provider.dart';

import '../../services/cadastro_sms_consent_android.dart';
import '../../services/cidades_brasil_service.dart';
import '../../services/firebase_functions_config.dart';
import '../../services/location_service.dart';
import '../../utils/cpf_perfil_usuario.dart';
import '../../widgets/dipertin_scroll_body.dart';
import '../../widgets/dipertin_versao_rodape.dart';
import 'login_screen.dart';
import 'widgets/termos_aceite_cadastro.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoTela = Color(0xFFF5F4F8);
const Color _textoPrimario = Color(0xFF1A1A2E);
const Color _textoMuted = Color(0xFF64748B);
const Color _erroCampo = Color(0xFFD32F2F);

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _cpfController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _codigoSmsController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _confirmarSenhaController = TextEditingController();
  final _focusCidade = FocusNode();

  bool _isLoading = false;
  /// Preenchidos ao escolher uma linha da lista IBGE (nome + UF corretos).
  String? _ufCadastroManual;
  String? _nomeCidadeSelecionada;
  bool _senhaOculta = true;
  bool _confirmarSenhaOculta = true;
  bool _aceiteTermosPrivacidade = false;

  bool _celularCompletoParaSms = false;
  bool _smsCodigoEnviado = false;
  bool _telefoneVerificadoSms = false;
  String? _ticketVerificacaoSms;
  bool _enviandoSms = false;
  bool _validandoCodigoSms = false;
  int _cooldownReenvioSms = 0;
  Timer? _timerCooldownSms;
  bool _entradaAnimada = false;
  String? _erroCampoNome;
  String? _erroCampoCpf;
  String? _erroCampoCidade;
  String? _erroCampoEmail;
  String? _erroCampoSenha;
  String? _erroCampoConfirmarSenha;
  String? _erroRequisitosCadastro;

  bool get _requisitosCadastroOk =>
      _telefoneVerificadoSms &&
      _ticketVerificacaoSms != null &&
      _ticketVerificacaoSms!.isNotEmpty &&
      _aceiteTermosPrivacidade;

  InputDecoration _decorCampo(
    String label,
    IconData icon, {
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      helperStyle: TextStyle(
        color: Colors.grey.shade600,
        fontSize: 12,
        height: 1.25,
      ),
      prefixIcon: Icon(icon, color: _diPertinRoxo.withValues(alpha: 0.88), size: 22),
      filled: true,
      fillColor: const Color(0xFFF9F8FC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(
        color: Colors.grey.shade700,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      floatingLabelStyle: const TextStyle(
        color: _diPertinRoxo,
        fontWeight: FontWeight.w700,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE0DEE8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _diPertinLaranja, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _erroCampo, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _erroCampo, width: 2),
      ),
      errorStyle: const TextStyle(
        color: _erroCampo,
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        height: 1.2,
      ),
    );
  }

  Widget _caixaSecao({
    required String titulo,
    required IconData icone,
    required Widget child,
    String? subtitulo,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _diPertinRoxo.withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icone, color: _diPertinRoxo, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    color: _textoPrimario,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          if (subtitulo != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitulo,
              style: const TextStyle(
                color: _textoMuted,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _itemChecklistRequisito(String rotulo, bool concluido) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            concluido
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 18,
            color: concluido ? Colors.green.shade700 : Colors.grey.shade400,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              rotulo,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: concluido ? Colors.green.shade800 : _textoMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _barraEtapas() {
    final etapaDados = _nomeController.text.trim().isNotEmpty &&
        CpfPerfilUsuario.cpfValido(_cpfController.text) &&
        _cidadeController.text.trim().isNotEmpty;
    final etapaCelular = _telefoneVerificadoSms;
    final etapaAcesso = _emailController.text.trim().isNotEmpty &&
        _senhaController.text.length >= 6 &&
        _senhaController.text == _confirmarSenhaController.text &&
        _aceiteTermosPrivacidade;

    Widget bolha(String rotulo, bool ativo, bool concluido) {
      final cor = concluido
          ? Colors.green.shade700
          : (ativo ? _diPertinRoxo : Colors.grey.shade300);
      return Expanded(
        child: Column(
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: cor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              rotulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: concluido
                    ? Colors.green.shade800
                    : (ativo ? _diPertinRoxo : _textoMuted),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        bolha('Dados', true, etapaDados),
        const SizedBox(width: 8),
        bolha('Celular', etapaDados, etapaCelular),
        const SizedBox(width: 8),
        bolha('Acesso', etapaCelular, etapaAcesso),
      ],
    );
  }

  void _limparErrosServidor() {
    setState(() {
      _erroCampoNome = null;
      _erroCampoCpf = null;
      _erroCampoCidade = null;
      _erroCampoEmail = null;
      _erroCampoSenha = null;
      _erroCampoConfirmarSenha = null;
      _erroRequisitosCadastro = null;
    });
  }

  String? _validarCampoNome(String? valor) {
    if (_erroCampoNome != null) return _erroCampoNome;
    if ((valor ?? '').trim().isEmpty) return 'Informe seu nome completo';
    return null;
  }

  String? _validarCampoCpf(String? valor) {
    if (_erroCampoCpf != null) return _erroCampoCpf;
    if ((valor ?? '').trim().isEmpty) return 'Informe seu CPF';
    if (!CpfPerfilUsuario.cpfValido(valor!)) {
      return 'CPF inválido. Confira os 11 dígitos.';
    }
    return null;
  }

  String? _validarCampoTelefone(String? valor) {
    if (_digitosTelefone(valor ?? '').length != 11) {
      return 'Informe um celular com 11 dígitos';
    }
    return null;
  }

  String? _validarCampoCidade() {
    if (_erroCampoCidade != null) return _erroCampoCidade;
    if (_cidadeController.text.trim().isEmpty) return 'Informe sua cidade';
    return null;
  }

  String? _validarCampoEmail(String? valor) {
    if (_erroCampoEmail != null) return _erroCampoEmail;
    final texto = (valor ?? '').trim();
    if (texto.isEmpty) return 'Informe seu e-mail';
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(texto)) {
      return 'Digite um e-mail válido (ex: seuemail@gmail.com)';
    }
    return null;
  }

  String? _validarCampoSenha(String? valor) {
    if (_erroCampoSenha != null) return _erroCampoSenha;
    if ((valor ?? '').isEmpty) return 'Crie uma senha';
    if ((valor ?? '').length < 6) return 'Mínimo de 6 caracteres';
    return null;
  }

  String? _validarCampoConfirmarSenha(String? valor) {
    if (_erroCampoConfirmarSenha != null) return _erroCampoConfirmarSenha;
    if ((valor ?? '').isEmpty) return 'Confirme sua senha';
    if (valor != _senhaController.text) return 'As senhas não coincidem';
    return null;
  }

  void _proximoCampo() {
    if (!_isLoading) {
      FocusScope.of(context).nextFocus();
    }
  }

  String _digitosTelefone(String texto) {
    return texto.replaceAll(RegExp(r'\D'), '');
  }

  void _onTelefoneParaSmsChanged() {
    final completo = _digitosTelefone(_telefoneController.text).length == 11;
    if (completo == _celularCompletoParaSms) return;
    setState(() {
      _celularCompletoParaSms = completo;
      if (!completo) {
        _smsCodigoEnviado = false;
        _telefoneVerificadoSms = false;
        _ticketVerificacaoSms = null;
        _codigoSmsController.clear();
        _timerCooldownSms?.cancel();
        _timerCooldownSms = null;
        _cooldownReenvioSms = 0;
        CadastroSmsConsentAndroid.parar();
      }
    });
  }

  Future<void> _iniciarOuRenovarEscutaSmsConsent() async {
    if (!CadastroSmsConsentAndroid.disponivel) return;
    if (!_smsCodigoEnviado || _telefoneVerificadoSms) return;
    await CadastroSmsConsentAndroid.iniciar(
      regex: r'\d{6}',
      onCodigo: (codigo) {
        if (!mounted || _telefoneVerificadoSms || !_smsCodigoEnviado) return;
        _codigoSmsController.value = TextEditingValue(text: codigo);
        setState(() {});
        Future.microtask(_validarCodigoSms);
      },
    );
  }

  void _iniciarCooldownReenvioSms() {
    _timerCooldownSms?.cancel();
    setState(() => _cooldownReenvioSms = 45);
    _timerCooldownSms = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _cooldownReenvioSms--;
        if (_cooldownReenvioSms <= 0) {
          t.cancel();
          _timerCooldownSms = null;
        }
      });
    });
  }

  String _mensagemErroFunctions(Object e) {
    if (e is FirebaseFunctionsException) {
      if (e.message != null && e.message!.isNotEmpty) return e.message!;
      switch (e.code) {
        case 'resource-exhausted':
          return 'Muitas tentativas de SMS. Aguarde alguns minutos.';
        case 'already-exists':
          return 'Já existe um cadastro com este CPF.';
        case 'invalid-argument':
          return 'Dados inválidos. Verifique o código ou o número.';
        case 'deadline-exceeded':
          return 'Código ou verificação expirados. Envie um novo SMS.';
        case 'internal':
        case 'unavailable':
          return 'Serviço temporariamente indisponível. Tente mais tarde.';
        default:
          return 'Não foi possível concluir. Tente novamente.';
      }
    }
    return 'Erro inesperado. Tente novamente.';
  }

  Future<void> _enviarCodigoSms() async {
    if (!_celularCompletoParaSms || _enviandoSms) return;
    final nomeTrim = _nomeController.text.trim();
    if (nomeTrim.isEmpty) {
      setState(() => _erroCampoNome = 'Preencha seu nome antes do SMS.');
      _formKey.currentState?.validate();
      return;
    }
    setState(() => _enviandoSms = true);
    try {
      final callable = appFirebaseFunctions.httpsCallable(
        'comteleCadastroTelefoneEnviarCodigo',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );
      await callable.call({
        'telefone': _telefoneController.text.trim(),
        'nome': nomeTrim,
      });
      if (!mounted) return;
      setState(() {
        _smsCodigoEnviado = true;
        _telefoneVerificadoSms = false;
        _ticketVerificacaoSms = null;
        _codigoSmsController.clear();
      });
      _iniciarCooldownReenvioSms();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Código enviado por SMS. Confira suas mensagens.'),
          backgroundColor: Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _iniciarOuRenovarEscutaSmsConsent();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemErroFunctions(e)),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _enviandoSms = false);
    }
  }

  Future<void> _validarCodigoSms() async {
    await CadastroSmsConsentAndroid.parar();
    if (!mounted) return;
    final codigo = _digitosTelefone(_codigoSmsController.text);
    if (codigo.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Digite o código de 6 dígitos enviado por SMS.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _validandoCodigoSms = true);
    try {
      final callable = appFirebaseFunctions.httpsCallable(
        'comteleCadastroTelefoneValidarCodigo',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
      );
      final res = await callable.call({
        'telefone': _telefoneController.text.trim(),
        'codigo': codigo,
      });
      final raw = res.data;
      String? ticket;
      if (raw is Map) {
        ticket = raw['ticketId'] as String?;
      }
      if (!mounted) return;
      if (ticket == null || ticket.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível confirmar o código. Tente novamente.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      setState(() {
        _telefoneVerificadoSms = true;
        _ticketVerificacaoSms = ticket;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Celular confirmado. Você já pode concluir o cadastro.'),
          backgroundColor: Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemErroFunctions(e)),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _validandoCodigoSms = false);
    }
  }

  /// Indica se [cadastroClienteSalvarPerfilInicial] já persistiu o perfil (leitura forçada ao servidor).
  Future<bool> _cadastroPerfilJaExisteNoServidor(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      if (!snap.exists) return false;
      final d = snap.data();
      if (d == null) return false;
      if (d['telefone_verificado_sms_em'] != null) return true;
      final cpfD =
          (d['cpf_digitos'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      return cpfD.length >= 11;
    } catch (_) {
      return false;
    }
  }

  /// Apaga tentativa local e, se o servidor **não** tiver perfil completo, remove o usuário do Auth.
  /// Retorna `true` se removeu a conta do Authentication (cadastro deve ser refeito).
  /// Retorna `false` se manteve a conta porque o perfil já está no Firestore (evita órfão Auth/doc).
  Future<bool> _reverterCadastroSeNecessario(UserCredential uc) async {
    final u = uc.user;
    if (u == null) return true;
    try {
      await FirebaseFirestore.instance.collection('users').doc(u.uid).delete();
    } catch (_) {}

    if (await _cadastroPerfilJaExisteNoServidor(u.uid)) {
      return false;
    }

    try {
      await u.delete();
    } catch (_) {}
    return true;
  }

  Future<void> _concluirCadastroClienteComSucesso(
    UserCredential userCredential,
  ) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
          'fcm_token': token,
          'ultimo_acesso': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cadastro realizado com sucesso!'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    final emailCadastrado = _emailController.text.trim();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(emailPreenchido: emailCadastrado),
      ),
      (route) => false,
    );
  }

  void _onCidadeChanged() {
    if (_erroCampoCidade != null) {
      setState(() => _erroCampoCidade = null);
    }
    if (_nomeCidadeSelecionada == null) return;
    if (LocationService.normalizar(_cidadeController.text) !=
        LocationService.normalizar(_nomeCidadeSelecionada!)) {
      setState(() {
        _nomeCidadeSelecionada = null;
        _ufCadastroManual = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    CidadesBrasilService.precarregar();
    _cidadeController.addListener(_onCidadeChanged);
    _telefoneController.addListener(_onTelefoneParaSmsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entradaAnimada = true);
    });
  }

  Future<void> _fazerCadastro() async {
    _limparErrosServidor();

    final cidadeErro = _validarCampoCidade();
    final formOk = _formKey.currentState?.validate() ?? false;
    if (cidadeErro != null) {
      setState(() => _erroCampoCidade = cidadeErro);
    }
    if (!formOk || cidadeErro != null) return;

    if (!_requisitosCadastroOk) {
      setState(() {
        if (!_telefoneVerificadoSms) {
          _erroRequisitosCadastro =
              'Confirme seu celular com o código SMS antes de cadastrar.';
        } else if (!_aceiteTermosPrivacidade) {
          _erroRequisitosCadastro =
              'Aceite os Termos de Uso e a Política de Privacidade.';
        }
      });
      return;
    }

    setState(() => _isLoading = true);

    final loc = context.read<LocationService>();
    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _senhaController.text.trim(),
          );

      final cidadeReg = _cidadeController.text.trim();
      final cidadeNormDigitada = LocationService.normalizar(cidadeReg);
      final veioDaLista = _nomeCidadeSelecionada != null &&
          cidadeNormDigitada ==
              LocationService.normalizar(_nomeCidadeSelecionada!);
      final ufStr =
          veioDaLista && _ufCadastroManual != null && _ufCadastroManual!.isNotEmpty
              ? _ufCadastroManual!
              : (loc.ufDetectado ?? '');
      final ufNormStr = veioDaLista && _ufCadastroManual != null
          ? LocationService.normalizar(_ufCadastroManual!)
          : loc.ufNormalizado;

      try {
        final salvarPerfil = appFirebaseFunctions.httpsCallable(
          'cadastroClienteSalvarPerfilInicial',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
        );
        await salvarPerfil.call({
          'ticketId': _ticketVerificacaoSms!,
          'telefone': _telefoneController.text.trim(),
          'nome': _nomeController.text.trim(),
          'cpf': _cpfController.text.trim(),
          'cidade': cidadeReg,
          'uf': ufStr,
          'cidade_normalizada': cidadeReg.isNotEmpty
              ? LocationService.normalizar(cidadeReg)
              : loc.cidadeNormalizada,
          'uf_normalizado': ufNormStr,
          'aceite_termos_versao': TermosCadastroFirestore.versaoDocumentos,
        });
      } on FirebaseFunctionsException catch (e) {
        final apagouAuth = await _reverterCadastroSeNecessario(userCredential);
        if (!apagouAuth) {
          await _concluirCadastroClienteComSucesso(userCredential);
          return;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_mensagemErroFunctions(e)),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      } catch (e) {
        final apagouAuth = await _reverterCadastroSeNecessario(userCredential);
        if (!apagouAuth) {
          await _concluirCadastroClienteComSucesso(userCredential);
          return;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_mensagemErroFunctions(e)),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      await _concluirCadastroClienteComSucesso(userCredential);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        if (e.code == 'weak-password') {
          setState(() => _erroCampoSenha = 'A senha é muito fraca.');
          _formKey.currentState?.validate();
        } else if (e.code == 'email-already-in-use') {
          setState(() => _erroCampoEmail = 'Este e-mail já está em uso.');
          _formKey.currentState?.validate();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro no cadastro: ${e.message ?? e.code}'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _painelVerificacaoSms() {
    return Container(
      key: ValueKey<bool>(_telefoneVerificadoSms),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F8FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _telefoneVerificadoSms
              ? Colors.green.shade200
              : const Color(0xFFE0DEE8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                _telefoneVerificadoSms
                    ? Icons.verified_rounded
                    : Icons.sms_outlined,
                color: _telefoneVerificadoSms ? Colors.green.shade700 : _diPertinRoxo,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _telefoneVerificadoSms
                      ? 'Celular confirmado por SMS'
                      : 'Confirme seu celular',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Colors.grey.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _telefoneVerificadoSms
                ? 'Este número foi validado e será associado à sua conta.'
                : _smsCodigoEnviado
                    ? 'Digite abaixo o código de 6 dígitos que você recebeu.'
                    : 'Toque em enviar para receber um código de 6 dígitos por SMS neste número.',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: Colors.grey.shade700,
            ),
          ),
          if (!_telefoneVerificadoSms) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: (_isLoading || _enviandoSms || !_celularCompletoParaSms)
                  ? null
                  : (_smsCodigoEnviado ? null : _enviarCodigoSms),
              icon: _enviandoSms
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 20),
              label: Text(
                _smsCodigoEnviado ? 'Código enviado' : 'Enviar código por SMS',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _diPertinRoxo,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _diPertinRoxo.withValues(alpha: 0.4),
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (_smsCodigoEnviado) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _codigoSmsController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  letterSpacing: 6,
                  fontWeight: FontWeight.w800,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autofillHints: CadastroSmsConsentAndroid.disponivel
                    ? const [AutofillHints.oneTimeCode]
                    : null,
                decoration: _decorCampo('Código SMS (6 dígitos)', Icons.pin_rounded)
                    .copyWith(counterText: ''),
                enabled: !_isLoading && !_validandoCodigoSms,
              ),
              if (CadastroSmsConsentAndroid.disponivel) ...[
                const SizedBox(height: 8),
                Text(
                  'Ao receber o SMS, o sistema pode pedir autorização para usar o código '
                  'neste aplicativo (SMS User Consent). Você pode recusar e digitar manualmente.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          (_isLoading || _validandoCodigoSms) ? null : _validarCodigoSms,
                      style: FilledButton.styleFrom(
                        backgroundColor: _diPertinLaranja,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _validandoCodigoSms
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Validar código',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: (_isLoading ||
                              _enviandoSms ||
                              _cooldownReenvioSms > 0 ||
                              !_smsCodigoEnviado)
                          ? null
                          : _enviarCodigoSms,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _diPertinRoxo,
                        side: BorderSide(color: _diPertinRoxo.withValues(alpha: 0.55)),
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _cooldownReenvioSms > 0
                            ? 'Reenviar (${_cooldownReenvioSms}s)'
                            : 'Reenviar SMS',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    CadastroSmsConsentAndroid.parar();
    _timerCooldownSms?.cancel();
    _cidadeController.removeListener(_onCidadeChanged);
    _telefoneController.removeListener(_onTelefoneParaSmsChanged);
    _nomeController.dispose();
    _cpfController.dispose();
    _telefoneController.dispose();
    _codigoSmsController.dispose();
    _cidadeController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _confirmarSenhaController.dispose();
    _focusCidade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: Navigator.canPop(context),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: _fundoTela,
        appBar: AppBar(
          title: const SizedBox.shrink(),
          backgroundColor: _diPertinRoxo,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: DiPertinScrollBody(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: AnimatedOpacity(
            opacity: _entradaAnimada ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/logo.png',
                      height: 88,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.storefront_rounded,
                          size: 68,
                          color: _diPertinRoxo.withValues(alpha: 0.9),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Criar sua conta',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _textoPrimario,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Peça das lojas da sua cidade com segurança.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _textoMuted,
                      fontSize: 14.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _barraEtapas(),
                  const SizedBox(height: 20),
                  _caixaSecao(
                    titulo: 'Seus dados',
                    icone: Icons.person_outline_rounded,
                    subtitulo:
                        'Usados para identificação e entrega na sua cidade.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _nomeController,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autovalidateMode:
                              AutovalidateMode.onUserInteraction,
                          validator: _validarCampoNome,
                          onChanged: (_) {
                            if (_erroCampoNome != null) {
                              setState(() => _erroCampoNome = null);
                            }
                          },
                          onFieldSubmitted: (_) => _proximoCampo(),
                          decoration: _decorCampo(
                            'Nome completo',
                            Icons.person_outline_rounded,
                          ),
                          enabled: !_isLoading,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _cpfController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            MaskedInputFormatter('000.000.000-00'),
                          ],
                          textInputAction: TextInputAction.next,
                          autovalidateMode:
                              AutovalidateMode.onUserInteraction,
                          validator: _validarCampoCpf,
                          onChanged: (_) {
                            if (_erroCampoCpf != null) {
                              setState(() => _erroCampoCpf = null);
                            }
                          },
                          onFieldSubmitted: (_) => _proximoCampo(),
                          decoration: _decorCampo('CPF', Icons.badge_outlined),
                          enabled: !_isLoading,
                        ),
                        const SizedBox(height: 14),
                        RawAutocomplete<CidadeSugestao>(
                          textEditingController: _cidadeController,
                          focusNode: _focusCidade,
                          displayStringForOption: (CidadeSugestao c) => c.nome,
                          optionsBuilder: (TextEditingValue tev) {
                            return CidadesBrasilService.buscar(tev.text);
                          },
                          onSelected: (CidadeSugestao c) {
                            setState(() {
                              _ufCadastroManual = c.ufSigla;
                              _nomeCidadeSelecionada = c.nome;
                              _erroCampoCidade = null;
                            });
                          },
                          fieldViewBuilder: (context, textEditingController,
                              focusNode, onFieldSubmitted) {
                            return TextField(
                              controller: textEditingController,
                              focusNode: focusNode,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) {
                                onFieldSubmitted();
                                _proximoCampo();
                              },
                              decoration: _decorCampo(
                                'Cidade',
                                Icons.location_city_outlined,
                                helperText:
                                    'Digite 3 letras para buscar (ex.: Tol → Toledo, Paraná).',
                              ).copyWith(errorText: _erroCampoCidade),
                              enabled: !_isLoading,
                            );
                          },
                          optionsViewBuilder: (context, onSelected, options) {
                            final list = options.toList();
                            if (list.isEmpty) return const SizedBox.shrink();
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                elevation: 6,
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                clipBehavior: Clip.antiAlias,
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxHeight: 260),
                                  child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    itemCount: list.length,
                                    itemBuilder: (context, index) {
                                      final opt = list[index];
                                      return InkWell(
                                        onTap: () => onSelected(opt),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                opt.nome,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 15,
                                                  color: _textoPrimario,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${opt.ufNome} · ${opt.ufSigla}',
                                                style: TextStyle(
                                                  color: Colors.grey.shade700,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _caixaSecao(
                    titulo: 'Confirme o celular',
                    icone: Icons.sms_outlined,
                    subtitulo:
                        'Enviamos um código por SMS para validar seu número.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _telefoneController,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            MaskedInputFormatter('(00) 00000-0000'),
                          ],
                          textInputAction: TextInputAction.next,
                          autovalidateMode:
                              AutovalidateMode.onUserInteraction,
                          validator: _validarCampoTelefone,
                          onFieldSubmitted: (_) => _proximoCampo(),
                          decoration: _decorCampo(
                            'Telefone (WhatsApp)',
                            Icons.phone_outlined,
                          ),
                          enabled: !_isLoading,
                        ),
                        if (_celularCompletoParaSms) ...[
                          const SizedBox(height: 14),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: _painelVerificacaoSms(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _caixaSecao(
                    titulo: 'Crie seu acesso',
                    icone: Icons.lock_outline_rounded,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          autovalidateMode:
                              AutovalidateMode.onUserInteraction,
                          validator: _validarCampoEmail,
                          onChanged: (_) {
                            if (_erroCampoEmail != null) {
                              setState(() => _erroCampoEmail = null);
                            }
                          },
                          onFieldSubmitted: (_) => _proximoCampo(),
                          decoration:
                              _decorCampo('E-mail', Icons.email_outlined),
                          enabled: !_isLoading,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _senhaController,
                          obscureText: _senhaOculta,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.next,
                          autovalidateMode:
                              AutovalidateMode.onUserInteraction,
                          validator: _validarCampoSenha,
                          onChanged: (_) {
                            if (_erroCampoSenha != null) {
                              setState(() => _erroCampoSenha = null);
                            }
                          },
                          onFieldSubmitted: (_) => _proximoCampo(),
                          decoration: _decorCampo(
                            'Senha',
                            Icons.lock_outline_rounded,
                            helperText: 'Mínimo 6 caracteres',
                          ).copyWith(
                            suffixIcon: IconButton(
                              tooltip: _senhaOculta
                                  ? 'Mostrar senha'
                                  : 'Ocultar senha',
                              onPressed: _isLoading
                                  ? null
                                  : () => setState(
                                        () => _senhaOculta = !_senhaOculta,
                                      ),
                              icon: Icon(
                                _senhaOculta
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: _diPertinRoxo.withValues(alpha: 0.75),
                                size: 22,
                              ),
                            ),
                          ),
                          enabled: !_isLoading,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _confirmarSenhaController,
                          obscureText: _confirmarSenhaOculta,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.done,
                          autovalidateMode:
                              AutovalidateMode.onUserInteraction,
                          validator: _validarCampoConfirmarSenha,
                          onChanged: (_) {
                            if (_erroCampoConfirmarSenha != null) {
                              setState(
                                () => _erroCampoConfirmarSenha = null,
                              );
                            }
                          },
                          onFieldSubmitted: (_) {
                            if (!_isLoading) _fazerCadastro();
                          },
                          decoration: _decorCampo(
                            'Confirmar senha',
                            Icons.lock_outline_rounded,
                          ).copyWith(
                            suffixIcon: IconButton(
                              tooltip: _confirmarSenhaOculta
                                  ? 'Mostrar senha'
                                  : 'Ocultar senha',
                              onPressed: _isLoading
                                  ? null
                                  : () => setState(
                                        () => _confirmarSenhaOculta =
                                            !_confirmarSenhaOculta,
                                      ),
                              icon: Icon(
                                _confirmarSenhaOculta
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: _diPertinRoxo.withValues(alpha: 0.75),
                                size: 22,
                              ),
                            ),
                          ),
                          enabled: !_isLoading,
                        ),
                        const SizedBox(height: 16),
                        TermosAceiteCadastroWidget(
                          aceito: _aceiteTermosPrivacidade,
                          onChanged: (v) => setState(() {
                            _aceiteTermosPrivacidade = v;
                            if (v) _erroRequisitosCadastro = null;
                          }),
                        ),
                        const SizedBox(height: 16),
                        _itemChecklistRequisito(
                          'Celular confirmado por SMS',
                          _telefoneVerificadoSms,
                        ),
                        _itemChecklistRequisito(
                          'Termos aceitos',
                          _aceiteTermosPrivacidade,
                        ),
                        if (_erroRequisitosCadastro != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _erroRequisitosCadastro!,
                            style: const TextStyle(
                              color: _erroCampo,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ] else if (!_requisitosCadastroOk) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Confirme o celular e aceite os termos para concluir.',
                            style: TextStyle(
                              color: _textoMuted,
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _isLoading ? null : _fazerCadastro,
                          style: FilledButton.styleFrom(
                            backgroundColor: _diPertinLaranja,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                _diPertinLaranja.withValues(alpha: 0.5),
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Cadastrar',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: _isLoading
                        ? null
                        : () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute<void>(
                                builder: (_) => const LoginScreen(),
                              ),
                            );
                          },
                    child: const Text(
                      'Já tem conta? Entrar',
                      style: TextStyle(
                        color: _diPertinRoxo,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('configuracoes')
                        .doc('status_app')
                        .snapshots(),
                    builder: (context, snapshot) {
                      var estavel = true;
                      if (snapshot.hasData && snapshot.data!.exists) {
                        final dados =
                            snapshot.data!.data() as Map<String, dynamic>?;
                        estavel = dados?['estavel'] ?? true;
                      }

                      return Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                estavel
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.warning_amber_rounded,
                                size: 18,
                                color: estavel
                                    ? Colors.green.shade700
                                    : Colors.amber.shade800,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  estavel
                                      ? 'Aplicativo operando normalmente.'
                                      : 'Aplicativo instável no momento.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: estavel
                                        ? Colors.green.shade700
                                        : Colors.amber.shade800,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const DiPertinVersaoRodape(),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

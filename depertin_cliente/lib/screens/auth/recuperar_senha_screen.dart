// Fluxo: e-mail → OTP (4 dígitos) → nova senha (Cloud Function com Admin SDK).
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/recuperacao_senha_service.dart';

class RecuperarSenhaScreen extends StatefulWidget {
  const RecuperarSenhaScreen({
    super.key,
    this.emailInicial,
    this.tituloAppBar,
  });

  /// Ex.: usuário logado em [ContaSegurancaScreen] — pré-preenche o e-mail.
  final String? emailInicial;

  /// Ex.: `Alterar senha` em vez de `Recuperação de senha`.
  final String? tituloAppBar;

  @override
  State<RecuperarSenhaScreen> createState() => _RecuperarSenhaScreenState();
}

class _RecuperarSenhaScreenState extends State<RecuperarSenhaScreen> {
  static const _roxo = Color(0xFF6A1B9A);
  static const _laranja = Color(0xFFFF8F00);
  static const _cooldownReenvioSegundos = 30;

  int _passo = 0;
  bool _carregando = false;
  /// 0 = pode solicitar novo código; >0 = aguardar (countdown).
  int _segundosRestantesReenvio = 0;
  Timer? _timerReenvio;
  bool _mostrarNovaSenha = false;
  bool _mostrarConfirmaSenha = false;

  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _novaSenhaCtrl = TextEditingController();
  final _confirmaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final e = widget.emailInicial?.trim();
    if (e != null && e.isNotEmpty) {
      _emailCtrl.text = e;
    }
  }

  bool get _emailPreenchidoPeloApp =>
      widget.emailInicial != null &&
      widget.emailInicial!.trim().isNotEmpty;

  /// ID de sessão no servidor após OTP válido (usado em [definirNovaSenha]).
  String _sessionIdRecuperacao = '';
  /// ID do documento de OTP (Firestore); necessário para validar o código.
  String _tokenIdRecuperacao = '';

  @override
  void dispose() {
    _timerReenvio?.cancel();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _novaSenhaCtrl.dispose();
    _confirmaCtrl.dispose();
    super.dispose();
  }

  void _cancelarCooldownReenvio() {
    _timerReenvio?.cancel();
    _timerReenvio = null;
    _segundosRestantesReenvio = 0;
  }

  void _iniciarCooldownReenvio() {
    _timerReenvio?.cancel();
    if (!mounted) return;
    setState(() => _segundosRestantesReenvio = _cooldownReenvioSegundos);
    _timerReenvio = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _timerReenvio?.cancel();
        return;
      }
      setState(() {
        if (_segundosRestantesReenvio <= 1) {
          _timerReenvio?.cancel();
          _timerReenvio = null;
          _segundosRestantesReenvio = 0;
        } else {
          _segundosRestantesReenvio--;
        }
      });
    });
  }

  bool get _podeReenviarCodigo =>
      !_carregando && _segundosRestantesReenvio == 0 && _emailValido(_emailCtrl.text);

  Future<void> _reenviarCodigo() async {
    if (!_podeReenviarCodigo) {
      if (_segundosRestantesReenvio > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Aguarde $_segundosRestantesReenvio s para solicitar um novo código.',
            ),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
      return;
    }
    final email = _emailCtrl.text.trim();
    setState(() => _carregando = true);
    try {
      final res = await RecuperacaoSenhaService.solicitarCodigo(email);
      final msg = res['mensagem'] ?? '';
      if (!mounted) return;
      setState(() {
        _otpCtrl.clear();
        _tokenIdRecuperacao = res['tokenId'] ?? '';
      });
      _iniciarCooldownReenvio();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: _roxo),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemErroFunctions(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  bool _emailValido(String e) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(e.trim());
  }

  /// Mínimo 8, pelo menos uma letra e um número (especial recomendado).
  bool _senhaAtendeMinimo(String s) {
    if (s.length < 8) return false;
    if (!RegExp(r'[A-Za-z]').hasMatch(s)) return false;
    if (!RegExp(r'\d').hasMatch(s)) return false;
    return true;
  }

  bool _senhaTemEspecial(String s) {
    return RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\/]').hasMatch(s);
  }

  String _mensagemErroFunctions(Object e) {
    if (e is FirebaseFunctionsException) {
      if (e.message != null && e.message!.isNotEmpty) return e.message!;
      switch (e.code) {
        case 'resource-exhausted':
          return 'Muitas tentativas. Aguarde alguns minutos e tente de novo.';
        case 'invalid-argument':
          return 'Dados inválidos. Verifique e tente novamente.';
        case 'internal':
          return 'Serviço temporariamente indisponível. Tente mais tarde.';
        default:
          return 'Não foi possível concluir. Tente novamente.';
      }
    }
    return 'Erro inesperado. Tente novamente.';
  }

  Future<void> _enviarCodigo() async {
    final email = _emailCtrl.text.trim();
    if (!_emailValido(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Digite um e-mail válido.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _carregando = true);
    try {
      final res = await RecuperacaoSenhaService.solicitarCodigo(email);
      final msg = res['mensagem'] ?? '';
      if (!mounted) return;
      setState(() {
        _passo = 1;
        _otpCtrl.clear();
        _tokenIdRecuperacao = res['tokenId'] ?? '';
      });
      _iniciarCooldownReenvio();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: _roxo),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemErroFunctions(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _validarOtp() async {
    final email = _emailCtrl.text.trim();
    final otp = _otpCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (otp.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o código de 4 dígitos.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _carregando = true);
    try {
      final sid = await RecuperacaoSenhaService.verificarOtpObterSessionId(
        email: email,
        otp: otp,
        tokenId: _tokenIdRecuperacao,
      );
      if (!mounted) return;
      setState(() {
        _sessionIdRecuperacao = sid;
        _passo = 2;
        _novaSenhaCtrl.clear();
        _confirmaCtrl.clear();
        _mostrarNovaSenha = false;
        _mostrarConfirmaSenha = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemErroFunctions(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _redefinirSenha() async {
    final a = _novaSenhaCtrl.text;
    final b = _confirmaCtrl.text;
    if (!_senhaAtendeMinimo(a)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A senha deve ter no mínimo 8 caracteres, com letras e números.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (a != b) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('As senhas não coincidem.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_sessionIdRecuperacao.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sessão expirada. Comece novamente.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _carregando = true);
    try {
      await RecuperacaoSenhaService.definirNovaSenha(
        sessionId: _sessionIdRecuperacao,
        newPassword: a,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Senha alterada. Entre com a nova senha.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemErroFunctions(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.tituloAppBar ?? 'Recuperação de senha',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: _roxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: AbsorbPointer(
        absorbing: _carregando,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _indicadorPasso(),
              const SizedBox(height: 24),
              if (_passo == 0) _painelEmail(),
              if (_passo == 1) _painelOtp(),
              if (_passo == 2) _painelNovaSenha(),
              if (_carregando) ...[
                const SizedBox(height: 24),
                const Center(
                  child: CircularProgressIndicator(color: _laranja),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _indicadorPasso() {
    return Row(
      children: List.generate(3, (i) {
        final ativo = i <= _passo;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
            height: 4,
            decoration: BoxDecoration(
              color: ativo ? _laranja : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  Widget _painelEmail() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _emailPreenchidoPeloApp
              ? 'Enviaremos um código de verificação para o e-mail da sua conta. '
                  'Depois você define a nova senha.'
              : 'Informe o e-mail da sua conta. Se existir cadastro, enviaremos um código.',
          style: TextStyle(color: Colors.grey.shade700, height: 1.35),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          readOnly: _emailPreenchidoPeloApp,
          decoration: const InputDecoration(
            labelText: 'E-mail',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _laranja,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: _carregando ? null : _enviarCodigo,
          child: const Text(
            'ENVIAR CÓDIGO',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _painelOtp() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Digite o código de 4 dígitos enviado para o seu e-mail.',
          style: TextStyle(color: Colors.grey.shade700, height: 1.35),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _otpCtrl,
          // Android: phone costuma abrir teclado só de dígitos; iOS: number sem decimal.
          keyboardType: defaultTargetPlatform == TargetPlatform.android
              ? TextInputType.phone
              : const TextInputType.numberWithOptions(
                  decimal: false,
                  signed: false,
                ),
          textInputAction: TextInputAction.done,
          enableSuggestions: false,
          autocorrect: false,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 28,
            letterSpacing: 12,
            fontWeight: FontWeight.w600,
          ),
          maxLength: 4,
          decoration: const InputDecoration(
            counterText: '',
            hintText: '0 0 0 0',
            border: OutlineInputBorder(),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _carregando
              ? null
              : () {
                  _cancelarCooldownReenvio();
                  setState(() {
                    _passo = 0;
                    _otpCtrl.clear();
                    _tokenIdRecuperacao = '';
                  });
                },
          child: const Text('Alterar e-mail'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _podeReenviarCodigo ? _reenviarCodigo : null,
          icon: Icon(
            Icons.refresh_rounded,
            color: _podeReenviarCodigo ? _roxo : Colors.grey,
          ),
          label: Text(
            _segundosRestantesReenvio > 0
                ? 'Novo código em ${_segundosRestantesReenvio}s'
                : 'Enviar novo código',
            style: TextStyle(
              color: _podeReenviarCodigo ? _roxo : Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: BorderSide(
              color: _podeReenviarCodigo ? _roxo : Colors.grey.shade400,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _laranja,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: _carregando ? null : _validarOtp,
          child: const Text(
            'CONTINUAR',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _painelNovaSenha() {
    final a = _novaSenhaCtrl.text;
    final temLetra = RegExp(r'[A-Za-z]').hasMatch(a);
    final temNum = RegExp(r'\d').hasMatch(a);
    final especial = _senhaTemEspecial(a);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Escolha uma nova senha segura.',
          style: TextStyle(color: Colors.grey.shade700, height: 1.35),
        ),
        const SizedBox(height: 8),
        Text(
          'Mínimo 8 caracteres, com letras e números. Caracteres especiais são recomendados.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _novaSenhaCtrl,
          obscureText: !_mostrarNovaSenha,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Nova senha',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _mostrarNovaSenha ? 'Ocultar senha' : 'Mostrar senha',
              icon: Icon(
                _mostrarNovaSenha
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Colors.grey.shade700,
              ),
              onPressed: () =>
                  setState(() => _mostrarNovaSenha = !_mostrarNovaSenha),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _chipRegra('8+ caracteres', a.length >= 8),
        _chipRegra('Pelo menos uma letra', temLetra),
        _chipRegra('Pelo menos um número', temNum),
        _chipRegra('Caractere especial (recomendado)', especial),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmaCtrl,
          obscureText: !_mostrarConfirmaSenha,
          decoration: InputDecoration(
            labelText: 'Confirmar senha',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip:
                  _mostrarConfirmaSenha ? 'Ocultar senha' : 'Mostrar senha',
              icon: Icon(
                _mostrarConfirmaSenha
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Colors.grey.shade700,
              ),
              onPressed: () => setState(
                () => _mostrarConfirmaSenha = !_mostrarConfirmaSenha,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _laranja,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: _carregando ? null : _redefinirSenha,
          child: const Text(
            'REDEFINIR SENHA',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _chipRegra(String label, bool ok) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: ok ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: ok ? Colors.green.shade800 : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

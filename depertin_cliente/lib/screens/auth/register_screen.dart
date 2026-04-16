// Arquivo: lib/screens/auth/register_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_multi_formatter/flutter_multi_formatter.dart';
import 'package:provider/provider.dart';
import '../../services/cidades_brasil_service.dart';
import '../../services/location_service.dart';
import 'widgets/termos_aceite_cadastro.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoTela = Color(0xFFF5F4F8);

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nomeController = TextEditingController();
  final _cpfController = TextEditingController();
  final _telefoneController = TextEditingController();
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
      fillColor: Colors.white,
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
    );
  }

  void _proximoCampo() {
    if (!_isLoading) {
      FocusScope.of(context).nextFocus();
    }
  }

  void _onCidadeChanged() {
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
  }

  Future<void> _fazerCadastro() async {
    if (_nomeController.text.isEmpty ||
        _cpfController.text.isEmpty ||
        _telefoneController.text.isEmpty ||
        _cidadeController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _senhaController.text.isEmpty ||
        _confirmarSenhaController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, preencha todos os campos.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!RegExp(
      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
    ).hasMatch(_emailController.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Por favor, digite um e-mail válido (ex: seuemail@gmail.com).',
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_senhaController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A senha deve ter no mínimo 6 caracteres.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_senhaController.text != _confirmarSenhaController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('As senhas não coincidem.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!_aceiteTermosPrivacidade) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Para concluir o cadastro, aceite os Termos de Uso e a '
            'Política de Privacidade.',
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
            ...TermosCadastroFirestore.camposAceite(),
            'nome': _nomeController.text.trim(),
            'cpf': _cpfController.text.trim(),
            'telefone': _telefoneController.text.trim(),
            'email': _emailController.text.trim(),
            'cidade': cidadeReg,
            'uf': ufStr,
            'cidade_normalizada': cidadeReg.isNotEmpty
                ? LocationService.normalizar(cidadeReg)
                : loc.cidadeNormalizada,
            'uf_normalizado': ufNormStr,
            'tipoUsuario': 'cliente',
            'role': 'cliente',
            'ativo': true,
            'status_conta': 'ativa',
            'onboarding_endereco_pendente': true,
            'onboarding_endereco_criado_em': FieldValue.serverTimestamp(),
            'cpf_alteracao_bloqueada': true,
            'dataCadastro': FieldValue.serverTimestamp(),
            'totalConcluido': 0,
            'saldo': 0,
          });

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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cadastro realizado com sucesso!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      String mensagemErro = 'Ocorreu um erro no cadastro.';
      if (e.code == 'weak-password') {
        mensagemErro = 'A senha é muito fraca.';
      } else if (e.code == 'email-already-in-use') {
        mensagemErro = 'Este e-mail já está em uso.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mensagemErro),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _cidadeController.removeListener(_onCidadeChanged);
    _nomeController.dispose();
    _cpfController.dispose();
    _telefoneController.dispose();
    _cidadeController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _confirmarSenhaController.dispose();
    _focusCidade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundoTela,
      appBar: AppBar(
        title: const Text(
          'Novo cadastro',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: _diPertinRoxo,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Image.asset(
                  'assets/logo.png',
                  height: 108,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.storefront_rounded,
                      size: 80,
                      color: _diPertinRoxo.withValues(alpha: 0.9),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Criar conta',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _diPertinRoxo,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Preencha seus dados para começar a usar o DiPertin.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Seus dados são usados para identificação e entrega na sua cidade.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nomeController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _proximoCampo(),
                decoration: _decorCampo('Nome completo', Icons.person_outline_rounded),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _cpfController,
                keyboardType: TextInputType.number,
                inputFormatters: [MaskedInputFormatter('000.000.000-00')],
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _proximoCampo(),
                decoration: _decorCampo('CPF', Icons.badge_outlined),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _telefoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [MaskedInputFormatter('(00) 00000-0000')],
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _proximoCampo(),
                decoration: _decorCampo('Telefone (WhatsApp)', Icons.phone_outlined),
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
                  });
                },
                fieldViewBuilder:
                    (context, textEditingController, focusNode, onFieldSubmitted) {
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
                    ),
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
                        constraints: const BoxConstraints(maxHeight: 260),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      opt.nome,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        color: Color(0xFF1A1A2E),
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
              const SizedBox(height: 14),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _proximoCampo(),
                decoration: _decorCampo('E-mail', Icons.email_outlined),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _senhaController,
                obscureText: _senhaOculta,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _proximoCampo(),
                decoration: _decorCampo(
                  'Senha',
                  Icons.lock_outline_rounded,
                  helperText: 'Mínimo 6 caracteres',
                ).copyWith(
                  suffixIcon: IconButton(
                    tooltip: _senhaOculta ? 'Mostrar senha' : 'Ocultar senha',
                    onPressed: _isLoading
                        ? null
                        : () {
                            setState(() => _senhaOculta = !_senhaOculta);
                          },
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
              TextField(
                controller: _confirmarSenhaController,
                obscureText: _confirmarSenhaOculta,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_isLoading) _fazerCadastro();
                },
                decoration: _decorCampo(
                  'Confirmar senha',
                  Icons.lock_outline_rounded,
                ).copyWith(
                  suffixIcon: IconButton(
                    tooltip: _confirmarSenhaOculta ? 'Mostrar senha' : 'Ocultar senha',
                    onPressed: _isLoading
                        ? null
                        : () {
                            setState(
                              () => _confirmarSenhaOculta = !_confirmarSenhaOculta,
                            );
                          },
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
              const SizedBox(height: 20),
              TermosAceiteCadastroWidget(
                aceito: _aceiteTermosPrivacidade,
                onChanged: (v) => setState(() => _aceiteTermosPrivacidade = v),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _fazerCadastro,
                style: FilledButton.styleFrom(
                  backgroundColor: _diPertinLaranja,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _diPertinLaranja.withValues(alpha: 0.5),
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
              const SizedBox(height: 24),
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('configuracoes')
                    .doc('status_app')
                    .snapshots(),
                builder: (context, snapshot) {
                  var estavel = true;
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final dados = snapshot.data!.data() as Map<String, dynamic>?;
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
                      Text(
                        'DiPertin v1.0.0',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/painel_admin_theme.dart';

/// Dados fiscais da empresa preenchidos no formulário.
class DadosEmpresaFiscal {
  final String razaoSocial;
  final String nomeFantasia;
  final String cnpj;
  final String ie;
  final String? im;
  final String regimeTributario;
  final String cnae;
  final String crt;
  final String logradouro;
  final String numero;
  final String complemento;
  final String bairro;
  final String cep;
  final String cidade;
  final String uf;
  final String telefone;
  final String emailFiscal;

  const DadosEmpresaFiscal({
    required this.razaoSocial,
    required this.nomeFantasia,
    required this.cnpj,
    required this.ie,
    this.im,
    required this.regimeTributario,
    required this.cnae,
    required this.crt,
    required this.logradouro,
    required this.numero,
    this.complemento = '',
    required this.bairro,
    required this.cep,
    required this.cidade,
    required this.uf,
    this.telefone = '',
    this.emailFiscal = '',
  });

  Map<String, dynamic> toJson() => {
        'razao_social': razaoSocial,
        'nome_fantasia': nomeFantasia,
        'cnpj': cnpj.replaceAll(RegExp(r'\D'), ''),
        'ie': ie.replaceAll(RegExp(r'\D'), ''),
        if (im != null && im!.isNotEmpty) 'im': im!.replaceAll(RegExp(r'\D'), ''),
        'regime_tributario': regimeTributario,
        'cnae': cnae.replaceAll(RegExp(r'\D'), ''),
        'crt': crt,
        'logradouro': logradouro,
        'numero': numero,
        'complemento': complemento,
        'bairro': bairro,
        'cep': cep.replaceAll(RegExp(r'\D'), ''),
        'cidade': cidade,
        'uf': uf,
        'telefone': telefone.replaceAll(RegExp(r'\D'), ''),
        'email_fiscal': emailFiscal,
      };

  factory DadosEmpresaFiscal.fromMap(Map<String, dynamic> map) {
    return DadosEmpresaFiscal(
      razaoSocial: (map['razao_social'] as String?) ?? '',
      nomeFantasia: (map['nome_fantasia'] as String?) ?? '',
      cnpj: (map['cnpj'] as String?) ?? '',
      ie: (map['ie'] as String?) ?? '',
      im: map['im'] as String?,
      regimeTributario: (map['regime_tributario'] as String?) ?? '',
      cnae: (map['cnae'] as String?) ?? '',
      crt: (map['crt'] as String?) ?? '',
      logradouro: (map['logradouro'] as String?) ?? '',
      numero: (map['numero'] as String?) ?? '',
      complemento: (map['complemento'] as String?) ?? '',
      bairro: (map['bairro'] as String?) ?? '',
      cep: (map['cep'] as String?) ?? '',
      cidade: (map['cidade'] as String?) ?? '',
      uf: (map['uf'] as String?) ?? '',
      telefone: (map['telefone'] as String?) ?? '',
      emailFiscal: (map['email_fiscal'] as String?) ?? '',
    );
  }

  /// Valida os campos obrigatórios e formatos.
  ///
  /// Nome fantasia é opcional (NF-e: xFant). MEI e demais regimes podem
  /// emitir apenas com razão social (xNome).
  String? validar() {
    if (razaoSocial.trim().isEmpty) return 'Razão social é obrigatória.';
    if (razaoSocial.trim().length < 3) return 'Razão social deve ter ao menos 3 caracteres.';
    if (cnpj.replaceAll(RegExp(r'\D'), '').length != 14) return 'CNPJ deve ter 14 dígitos.';
    if (!_validarCnpjDigitos(cnpj.replaceAll(RegExp(r'\D'), ''))) return 'CNPJ inválido (dígitos verificadores não conferem).';
    final regimeNorm = regimeTributario.trim().toLowerCase().replaceAll(' ', '_');
    final ieIsentaMei = regimeNorm == 'mei';
    if (!ieIsentaMei && ie.replaceAll(RegExp(r'\D'), '').isEmpty) {
      return 'Inscrição estadual é obrigatória.';
    }
    if (regimeTributario.isEmpty) return 'Regime tributário é obrigatório.';
    if (cnae.replaceAll(RegExp(r'\D'), '').length != 7) return 'CNAE deve ter 7 dígitos.';
    if (crt.isEmpty) return 'CRT é obrigatório.';
    if (logradouro.trim().isEmpty) return 'Logradouro é obrigatório.';
    if (numero.trim().isEmpty) return 'Número é obrigatório.';
    if (bairro.trim().isEmpty) return 'Bairro é obrigatório.';
    if (cep.replaceAll(RegExp(r'\D'), '').length != 8) return 'CEP deve ter 8 dígitos.';
    if (cidade.trim().isEmpty) return 'Cidade é obrigatória.';
    if (uf.trim().length != 2) return 'UF deve ter 2 caracteres.';
    if (emailFiscal.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(emailFiscal)) {
      return 'E-mail fiscal inválido.';
    }
    return null;
  }

  static bool _validarCnpjDigitos(String cnpjNumeros) {
    if (cnpjNumeros.length != 14) return false;
    final digitos = cnpjNumeros.split('').map(int.parse).toList();

    int calcDigito(List<int> pesos) {
      int soma = 0;
      for (int i = 0; i < pesos.length; i++) {
        soma += digitos[i] * pesos[i];
      }
      final resto = soma % 11;
      return resto < 2 ? 0 : 11 - resto;
    }

    final pesos1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    final digito1 = calcDigito(pesos1);
    if (digito1 != digitos[12]) return false;

    final pesos2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    final digito2 = calcDigito(pesos2);
    if (digito2 != digitos[13]) return false;

    return true;
  }
}

/// Modal de preenchimento dos dados fiscais da empresa.
class FiscalDadosEmpresaModal extends StatefulWidget {
  final DadosEmpresaFiscal? iniciais;

  const FiscalDadosEmpresaModal({super.key, this.iniciais});

  /// Abre o modal e retorna os dados preenchidos, ou `null` se cancelado.
  static Future<DadosEmpresaFiscal?> mostrar(
    BuildContext context, {
    DadosEmpresaFiscal? iniciais,
  }) {
    return showDialog<DadosEmpresaFiscal>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => FiscalDadosEmpresaModal(iniciais: iniciais),
    );
  }

  @override
  State<FiscalDadosEmpresaModal> createState() =>
      _FiscalDadosEmpresaModalState();
}

class _FiscalDadosEmpresaModalState extends State<FiscalDadosEmpresaModal> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _razaoSocialCtrl;
  late final TextEditingController _nomeFantasiaCtrl;
  late final TextEditingController _cnpjCtrl;
  late final TextEditingController _ieCtrl;
  late final TextEditingController _imCtrl;
  late final TextEditingController _cnaeCtrl;
  late final TextEditingController _logradouroCtrl;
  late final TextEditingController _numeroCtrl;
  late final TextEditingController _complementoCtrl;
  late final TextEditingController _bairroCtrl;
  late final TextEditingController _cepCtrl;
  late final TextEditingController _cidadeCtrl;
  late final TextEditingController _telefoneCtrl;
  late final TextEditingController _emailFiscalCtrl;

  String _regimeTributario = '';
  String _crt = '';
  String _uf = '';

  bool _salvando = false;

  static const _roxo = DiPertinTheme.primaryRoxo;

  static const List<String> _regimes = [
    'Simples Nacional',
    'Simples Nacional — MEI',
    'Regime Normal',
  ];

  static const List<String> _crts = [
    '1 — Simples Nacional',
    '2 — Simples Nacional — MEI',
    '3 — Regime Normal',
  ];

  static const List<String> _ufs = [
    'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO',
    'MA', 'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE', 'PI',
    'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO',
  ];

  @override
  void initState() {
    super.initState();
    final i = widget.iniciais;
    _razaoSocialCtrl = TextEditingController(text: i?.razaoSocial ?? '');
    _nomeFantasiaCtrl = TextEditingController(text: i?.nomeFantasia ?? '');
    _cnpjCtrl = TextEditingController(text: i?.cnpj ?? '');
    _ieCtrl = TextEditingController(text: i?.ie ?? '');
    _imCtrl = TextEditingController(text: i?.im ?? '');
    _cnaeCtrl = TextEditingController(text: i?.cnae ?? '');
    _logradouroCtrl = TextEditingController(text: i?.logradouro ?? '');
    _numeroCtrl = TextEditingController(text: i?.numero ?? '');
    _complementoCtrl = TextEditingController(text: i?.complemento ?? '');
    _bairroCtrl = TextEditingController(text: i?.bairro ?? '');
    _cepCtrl = TextEditingController(text: i?.cep ?? '');
    _cidadeCtrl = TextEditingController(text: i?.cidade ?? '');
    _telefoneCtrl = TextEditingController(text: i?.telefone ?? '');
    _emailFiscalCtrl = TextEditingController(text: i?.emailFiscal ?? '');
    _regimeTributario = i?.regimeTributario ?? '';
    _crt = i?.crt ?? '';
    _uf = i?.uf ?? '';
  }

  @override
  void dispose() {
    _razaoSocialCtrl.dispose();
    _nomeFantasiaCtrl.dispose();
    _cnpjCtrl.dispose();
    _ieCtrl.dispose();
    _imCtrl.dispose();
    _cnaeCtrl.dispose();
    _logradouroCtrl.dispose();
    _numeroCtrl.dispose();
    _complementoCtrl.dispose();
    _bairroCtrl.dispose();
    _cepCtrl.dispose();
    _cidadeCtrl.dispose();
    _telefoneCtrl.dispose();
    _emailFiscalCtrl.dispose();
    super.dispose();
  }

  String? _validarCnpj(String? value) {
    final numeros = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (numeros.length != 14) return 'CNPJ deve ter 14 dígitos.';
    if (!DadosEmpresaFiscal._validarCnpjDigitos(numeros)) {
      return 'CNPJ inválido.';
    }
    return null;
  }

  void _salvar() {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _salvando = true);

    final dados = DadosEmpresaFiscal(
      razaoSocial: _razaoSocialCtrl.text.trim(),
      nomeFantasia: _nomeFantasiaCtrl.text.trim(),
      cnpj: _cnpjCtrl.text.trim(),
      ie: _ieCtrl.text.trim(),
      im: _imCtrl.text.trim().isEmpty ? null : _imCtrl.text.trim(),
      regimeTributario: _regimeTributario,
      cnae: _cnaeCtrl.text.trim(),
      crt: _crt,
      logradouro: _logradouroCtrl.text.trim(),
      numero: _numeroCtrl.text.trim(),
      complemento: _complementoCtrl.text.trim(),
      bairro: _bairroCtrl.text.trim(),
      cep: _cepCtrl.text.trim(),
      cidade: _cidadeCtrl.text.trim(),
      uf: _uf,
      telefone: _telefoneCtrl.text.trim(),
      emailFiscal: _emailFiscalCtrl.text.trim(),
    );

    Navigator.of(context).pop(dados);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 40,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: isMobile ? null : 820,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSecao('Identificação da Empresa', Icons.business),
                      const SizedBox(height: 12),
                      _buildLinhaCampos([
                        Expanded(
                          child: _buildTextField(
                            label: 'Razão Social',
                            controller: _razaoSocialCtrl,
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Obrigatório'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            label: 'Nome Fantasia (opcional)',
                            controller: _nomeFantasiaCtrl,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _buildLinhaCampos([
                        Expanded(
                          child: _buildTextField(
                            label: 'CNPJ',
                            controller: _cnpjCtrl,
                            hint: '00.000.000/0000-00',
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              _CnpjInputFormatter(),
                            ],
                            keyboardType: TextInputType.number,
                            validator: _validarCnpj,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            label: _regimeTributario.toLowerCase() == 'mei'
                                ? 'Inscrição Estadual (opcional para MEI)'
                                : 'Inscrição Estadual',
                            controller: _ieCtrl,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (_regimeTributario.toLowerCase() == 'mei') {
                                return null;
                              }
                              return v == null ||
                                      v.replaceAll(RegExp(r'\D'), '').isEmpty
                                  ? 'Obrigatório'
                                  : null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            label: 'Inscrição Municipal',
                            controller: _imCtrl,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _buildLinhaCampos([
                        Expanded(
                          flex: 2,
                          child: _buildDropdown(
                            label: 'Regime Tributário',
                            value: _regimeTributario,
                            items: _regimes,
                            onChanged: (v) =>
                                setState(() => _regimeTributario = v!),
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Obrigatório' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            label: 'CNAE',
                            controller: _cnaeCtrl,
                            hint: '7 dígitos',
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(7),
                            ],
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              final d = v?.replaceAll(RegExp(r'\D'), '') ?? '';
                              if (d.length != 7) return 'Exatos 7 dígitos';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDropdown(
                            label: 'CRT',
                            value: _crt,
                            items: _crts,
                            onChanged: (v) =>
                                setState(() => _crt = v!),
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Obrigatório' : null,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 28),
                      _buildSecao('Endereço', Icons.location_on_outlined),
                      const SizedBox(height: 12),
                      _buildLinhaCampos([
                        Expanded(
                          flex: 3,
                          child: _buildTextField(
                            label: 'Logradouro',
                            controller: _logradouroCtrl,
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Obrigatório'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            label: 'Número',
                            controller: _numeroCtrl,
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Obrigatório'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: _buildTextField(
                            label: 'Complemento',
                            controller: _complementoCtrl,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _buildLinhaCampos([
                        Expanded(
                          child: _buildTextField(
                            label: 'Bairro',
                            controller: _bairroCtrl,
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Obrigatório'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            label: 'CEP',
                            controller: _cepCtrl,
                            hint: '00000-000',
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              _CepInputFormatter(),
                            ],
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              final d = v?.replaceAll(RegExp(r'\D'), '') ?? '';
                              if (d.length != 8) return 'CEP deve ter 8 dígitos';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            label: 'Cidade',
                            controller: _cidadeCtrl,
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Obrigatório'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDropdown(
                            label: 'UF',
                            value: _uf,
                            items: _ufs,
                            onChanged: (v) =>
                                setState(() => _uf = v!),
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Obrigatório' : null,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 28),
                      _buildSecao('Contato', Icons.contact_phone_outlined),
                      const SizedBox(height: 12),
                      _buildLinhaCampos([
                        Expanded(
                          child: _buildTextField(
                            label: 'Telefone',
                            controller: _telefoneCtrl,
                            hint: '(00) 00000-0000',
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              _TelefoneInputFormatter(),
                            ],
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            label: 'E-mail Fiscal',
                            controller: _emailFiscalCtrl,
                            keyboardType: TextInputType.emailAddress,
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.assignment_outlined,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dados da Empresa',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Informações fiscais obrigatórias para emissão de NF-e',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecao(String titulo, IconData icone) {
    return Row(
      children: [
        Icon(icone, size: 20, color: _roxo),
        const SizedBox(width: 8),
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(height: 1, color: _roxo.withValues(alpha: 0.15)),
        ),
      ],
    );
  }

  Widget _buildLinhaCampos(List<Widget> campos) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 500) {
          return Column(
            children: campos
                .map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: c,
                    ))
                .toList(),
          );
        }
        return Row(children: campos);
      },
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hint,
    List<TextInputFormatter>? inputFormatters,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF6A1B9A), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        labelStyle: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w500,
        ),
      ),
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
    String? Function(String?)? validator,
  }) {
    return DropdownButtonFormField<String>(
      value: value.isEmpty ? null : value,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF6A1B9A), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        labelStyle: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w500,
        ),
      ),
      items: items
          .map((item) => DropdownMenuItem(
                value: item,
                child: Text(item, style: const TextStyle(fontSize: 14)),
              ))
          .toList(),
      onChanged: onChanged,
      validator: validator,
      dropdownColor: Colors.white,
      icon: const Icon(Icons.expand_more, color: Color(0xFF6A1B9A)),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _salvando
                ? null
                : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            child: const Text(
              'Cancelar',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _salvando ? null : _salvar,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6A1B9A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
              shadowColor: const Color(0xFF6A1B9A).withValues(alpha: 0.3),
            ),
            child: _salvando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Salvar Dados',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Formatador de CNPJ: 00.000.000/0000-00
class _CnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue novo) {
    final digits = novo.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 14) return old;

    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 2 || i == 5) buf.write('.');
      if (i == 8) buf.write('/');
      if (i == 12) buf.write('-');
      buf.write(digits[i]);
    }
    return TextEditingValue(
      text: buf.toString(),
      selection: TextSelection.collapsed(offset: buf.length),
    );
  }
}

/// Formatador de CEP: 00000-000
class _CepInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue novo) {
    final digits = novo.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 8) return old;

    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 5) buf.write('-');
      buf.write(digits[i]);
    }
    return TextEditingValue(
      text: buf.toString(),
      selection: TextSelection.collapsed(offset: buf.length),
    );
  }
}

/// Formatador de telefone: (00) 00000-0000
class _TelefoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue novo) {
    final digits = novo.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 11) return old;

    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 0) buf.write('(');
      if (i == 2) buf.write(') ');
      if (i == 7) buf.write('-');
      buf.write(digits[i]);
    }
    return TextEditingValue(
      text: buf.toString(),
      selection: TextSelection.collapsed(offset: buf.length),
    );
  }
}

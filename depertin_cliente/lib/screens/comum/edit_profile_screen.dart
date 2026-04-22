// Arquivo: lib/screens/comum/edit_profile_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
// === NOVOS PACOTES PARA A FOTO ===
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_multi_formatter/flutter_multi_formatter.dart';
import '../../services/location_service.dart';
import '../../services/permissoes_app_service.dart';
import '../../utils/cpf_perfil_usuario.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class EditProfileScreen extends StatefulWidget {
  final String nomeAtual;
  final String enderecoAtual;
  final String? role;
  final String? nomeLojaAtual;

  const EditProfileScreen({
    super.key,
    required this.nomeAtual,
    required this.enderecoAtual,
    this.role,
    this.nomeLojaAtual,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nomeController;
  final TextEditingController _cpfController = TextEditingController();
  final TextEditingController _telefoneController = TextEditingController();
  final TextEditingController _ruaC = TextEditingController();
  final TextEditingController _numeroC = TextEditingController();
  final TextEditingController _bairroC = TextEditingController();
  final TextEditingController _cidadeC = TextEditingController();
  final TextEditingController _complementoC = TextEditingController();

  bool _salvando = false;
  bool _buscandoLocalizacao = false;
  bool _carregandoDados = true;
  bool _cpfAlteracaoBloqueada = false;
  String _ufCapturado = '';

  // === VARIÁVEIS DA FOTO ===
  File? _imagemSelecionada;
  String _urlFotoAtual = '';
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController(text: widget.nomeAtual);
    _carregarDadosDoBanco();
  }

  // BUSCA O ENDEREÇO E A FOTO ATUAL DO FIREBASE
  Future<void> _carregarDadosDoBanco() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        var doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          var dados = doc.data() as Map<String, dynamic>;

          setState(() {
            // Pega a foto atual se existir
            _urlFotoAtual = dados['foto_perfil'] ?? '';

            // Pega o endereço
            if (dados.containsKey('endereco_entrega_padrao') &&
                dados['endereco_entrega_padrao'] is Map) {
              var end = dados['endereco_entrega_padrao'];
              _ruaC.text = end['rua'] ?? '';
              _numeroC.text = end['numero'] ?? '';
              _bairroC.text = end['bairro'] ?? '';
              _cidadeC.text = end['cidade'] ?? '';
              _complementoC.text = end['complemento'] ?? '';
            } else if (widget.enderecoAtual.isNotEmpty) {
              _ruaC.text = widget.enderecoAtual;
            }

            _cpfAlteracaoBloqueada = CpfPerfilUsuario.edicaoBloqueada(dados);
            final cpfSalvo = (dados['cpf'] ?? '').toString();
            final dCpf = CpfPerfilUsuario.somenteDigitos(cpfSalvo);
            if (dCpf.length == 11) {
              _cpfController.text = CpfPerfilUsuario.comMascara11(dCpf);
            } else if (cpfSalvo.isNotEmpty) {
              _cpfController.text = cpfSalvo;
            }

            final telefoneSalvo = (dados['telefone'] ?? '').toString();
            final dTel = telefoneSalvo.replaceAll(RegExp(r'[^0-9]'), '');
            if (dTel.isNotEmpty) {
              _telefoneController.text = _mascararTelefoneBr(dTel);
            } else if (telefoneSalvo.isNotEmpty) {
              _telefoneController.text = telefoneSalvo;
            }
          });
        }
      } catch (e) {
        debugPrint("Erro ao carregar dados: $e");
      }
    }
    setState(() => _carregandoDados = false);
  }

  // === FUNÇÃO PARA ESCOLHER A FOTO (CÂMARA OU GALERIA) ===
  Future<void> _escolherImagem(ImageSource fonte) async {
    final ResultadoPermissao pr = fonte == ImageSource.camera
        ? await PermissoesAppService.garantirCamera()
        : await PermissoesAppService.garantirGaleriaFotos();
    if (!mounted) return;
    if (pr != ResultadoPermissao.concedida) {
      if (fonte == ImageSource.camera) {
        PermissoesFeedback.camera(context, pr);
      } else {
        PermissoesFeedback.galeria(context, pr);
      }
      return;
    }
    try {
      final XFile? fotoEscolhida = await _picker.pickImage(
        source: fonte,
        imageQuality:
            70, // Comprime a foto para não gastar muita internet/espaço
        maxWidth: 800,
      );

      if (fotoEscolhida != null) {
        setState(() {
          _imagemSelecionada = File(fotoEscolhida.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao selecionar imagem.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // === MENU INFERIOR PARA ESCOLHER A ORIGEM DA FOTO ===
  void _mostrarMenuDeFoto() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: [
              const Padding(
                padding: EdgeInsets.all(15.0),
                child: Text(
                  'Foto do perfil',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: diPertinRoxo,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera, color: diPertinLaranja),
                title: const Text('Tirar foto agora'),
                onTap: () async {
                  Navigator.pop(context);
                  // Evita abrir permissão/picker enquanto a rota do sheet ainda fecha.
                  await Future<void>.delayed(const Duration(milliseconds: 200));
                  if (!mounted) return;
                  await _escolherImagem(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: diPertinLaranja,
                ),
                title: const Text('Escolher da galeria'),
                onTap: () async {
                  Navigator.pop(context);
                  await Future<void>.delayed(const Duration(milliseconds: 200));
                  if (!mounted) return;
                  await _escolherImagem(ImageSource.gallery);
                },
              ),
              if (_urlFotoAtual.isNotEmpty || _imagemSelecionada != null)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text(
                    'Remover Foto',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _imagemSelecionada = null;
                      _urlFotoAtual = ''; // Limpa a foto
                    });
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _obterLocalizacaoAtual() async {
    setState(() => _buscandoLocalizacao = true);
    try {
      final ResultadoLocalizacao loc =
          await PermissoesAppService.garantirLocalizacao();
      if (!mounted) return;
      if (loc != ResultadoLocalizacao.ok) {
        await PermissoesFeedback.localizacao(context, loc);
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      final Placemark place = placemarks[0];
      final String cidadeDetectada = place.locality?.isNotEmpty == true
          ? place.locality!
          : (place.subAdministrativeArea?.isNotEmpty == true
                ? place.subAdministrativeArea!
                : (place.administrativeArea ?? ""));

      final String? ufDetectado =
          LocationService.extrairUf(place.administrativeArea);

      setState(() {
        _ruaC.text = place.thoroughfare ?? place.street ?? "";
        _bairroC.text = place.subLocality ?? "";
        _cidadeC.text = cidadeDetectada;
        _numeroC.text = place.subThoroughfare ?? "";
        _ufCapturado = ufDetectado?.toUpperCase() ?? '';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Localização capturada. Revise os dados antes de salvar.',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro no GPS. Digite manualmente.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _buscandoLocalizacao = false);
    }
  }

  // === LÓGICA TURBINADA DE SALVAR (PRONTA PARA O PAINEL WEB) ===
  Future<void> _salvarPerfil() async {
    if (_nomeController.text.isEmpty ||
        _ruaC.text.isEmpty ||
        _numeroC.text.isEmpty ||
        _bairroC.text.isEmpty ||
        _cidadeC.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha Nome, Rua, Número, Bairro e Cidade!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_cpfAlteracaoBloqueada) {
      final dig = CpfPerfilUsuario.somenteDigitos(_cpfController.text);
      if (dig.isNotEmpty && !CpfPerfilUsuario.digitosCpfValidos(dig)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('CPF inválido. Confira os 11 dígitos.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final telefoneBruto = _telefoneController.text.trim();
    if (telefoneBruto.isNotEmpty && !_telefoneValido(telefoneBruto)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Telefone inválido. Informe DDD + número com 10 ou 11 dígitos.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        String linkDaFoto = _urlFotoAtual;

        // SE O CLIENTE ESCOLHEU UMA FOTO NOVA, FAZEMOS O UPLOAD!
        if (_imagemSelecionada != null) {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('fotos_perfil')
              .child('${user.uid}.jpg');

          UploadTask uploadTask = storageRef.putFile(_imagemSelecionada!);
          TaskSnapshot snapshot = await uploadTask;
          linkDaFoto = await snapshot.ref.getDownloadURL();
        }

        String cidadeFinal = _cidadeC.text.trim().toLowerCase();

        Map<String, dynamic> enderecoCompleto = {
          'rua': _ruaC.text.trim(),
          'numero': _numeroC.text.trim(),
          'bairro': _bairroC.text.trim(),
          'cidade': cidadeFinal,
          'complemento': _complementoC.text.trim(),
        };

        final telefoneDigitos =
            _telefoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
        final String telefoneParaSalvar = telefoneDigitos.isEmpty
            ? ''
            : _mascararTelefoneBr(telefoneDigitos);

        Map<String, dynamic> dadosParaSalvar = {
          'nome': _nomeController.text.trim(),
          'endereco_entrega_padrao': enderecoCompleto,
          'cidade': cidadeFinal,
          'foto_perfil': linkDaFoto,
          'telefone': telefoneParaSalvar,
          'role': widget.role ?? 'cliente',
          'perfil_completo': true,
        };

        if (_ufCapturado.isNotEmpty) {
          dadosParaSalvar['uf'] = _ufCapturado;
          dadosParaSalvar['cidade_normalizada'] =
              LocationService.normalizar(cidadeFinal);
          dadosParaSalvar['uf_normalizado'] =
              LocationService.extrairUf(_ufCapturado) ??
                  LocationService.normalizar(_ufCapturado);
        }

        if (_urlFotoAtual.isEmpty && _imagemSelecionada == null) {
          dadosParaSalvar['foto_perfil'] = '';
        }

        if (!_cpfAlteracaoBloqueada) {
          final dig = CpfPerfilUsuario.somenteDigitos(_cpfController.text);
          if (dig.isNotEmpty) {
            dadosParaSalvar['cpf'] = CpfPerfilUsuario.comMascara11(dig);
            dadosParaSalvar['cpf_alteracao_bloqueada'] = true;
          }
        }

        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update(dadosParaSalvar);

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Perfil atualizado com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  /// Aplica máscara `(00) 0000-0000` ou `(00) 00000-0000` sobre um texto
  /// contendo apenas dígitos.
  String _mascararTelefoneBr(String digitosBrutos) {
    String d = digitosBrutos.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('55') && d.length > 11) {
      d = d.substring(2);
    }
    if (d.length > 11) d = d.substring(0, 11);
    if (d.length == 11) {
      return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
    }
    if (d.length == 10) {
      return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
    }
    return d;
  }

  bool _telefoneValido(String bruto) {
    final d = bruto.replaceAll(RegExp(r'[^0-9]'), '');
    return d.length == 10 || d.length == 11;
  }

  Widget _tituloSecao(String titulo, String subtitulo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade800,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitulo,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _cardPerfil({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E6ED)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      appBar: AppBar(
        title: const Text(
          'Editar perfil',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: diPertinRoxo,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _carregandoDados
          ? const Center(child: CircularProgressIndicator(color: diPertinRoxo))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _cardPerfil(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _tituloSecao(
                          'Foto do perfil',
                          'Toque no ícone da câmera para alterar.',
                        ),
                        const SizedBox(height: 18),
                        Center(
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: diPertinRoxo.withValues(alpha: 0.22),
                                    width: 2,
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 50,
                                  backgroundColor:
                                      diPertinRoxo.withValues(alpha: 0.1),
                                  backgroundImage: _imagemSelecionada != null
                                      ? FileImage(_imagemSelecionada!)
                                      : (_urlFotoAtual.isNotEmpty
                                            ? NetworkImage(_urlFotoAtual)
                                            : null)
                                          as ImageProvider?,
                                  child: (_imagemSelecionada == null &&
                                          _urlFotoAtual.isEmpty)
                                      ? const Icon(
                                          Icons.person,
                                          size: 60,
                                          color: diPertinRoxo,
                                        )
                                      : null,
                                ),
                              ),
                              GestureDetector(
                                onTap: _mostrarMenuDeFoto,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    color: diPertinLaranja,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0x33000000),
                                        blurRadius: 6,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _cardPerfil(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _tituloSecao(
                          'Dados pessoais',
                          'Nome e documento usados nos pedidos e comunicações.',
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _nomeController,
                          label: 'Nome completo',
                          icon: Icons.person_outline_rounded,
                        ),
                        const SizedBox(height: 14),
                        if (_cpfAlteracaoBloqueada) ...[
                          _buildTextField(
                            controller: _cpfController,
                            label: 'CPF',
                            icon: Icons.badge_outlined,
                            readOnly: true,
                            keyboardType: TextInputType.number,
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 2,
                              top: 8,
                              bottom: 2,
                            ),
                            child: Text(
                              'Para alterar o CPF, fale com o suporte pelo app.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ] else ...[
                          _buildTextField(
                            controller: _cpfController,
                            label: 'CPF',
                            icon: Icons.badge_outlined,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              MaskedInputFormatter('000.000.000-00'),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 2,
                              top: 8,
                              bottom: 2,
                            ),
                            child: Text(
                              'Após salvar com CPF válido, ele não poderá ser alterado aqui.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        _buildTextField(
                          controller: _telefoneController,
                          label: 'Telefone / WhatsApp',
                          icon: Icons.phone_android_rounded,
                          keyboardType: TextInputType.phone,
                          textCapitalization: TextCapitalization.none,
                          inputFormatters: [
                            MaskedInputFormatter('(00) 00000-0000'),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 2,
                            top: 8,
                            bottom: 2,
                          ),
                          child: Text(
                            'Usado pelo entregador para entrar em contato durante a entrega.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _cardPerfil(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _tituloSecao(
                          'Endereço de entrega',
                          'Usado para entregas e vitrine na sua região.',
                        ),
                        const SizedBox(height: 14),
                        FilledButton.tonalIcon(
                          onPressed: _buscandoLocalizacao
                              ? null
                              : _obterLocalizacaoAtual,
                          icon: _buscandoLocalizacao
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: diPertinRoxo,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.my_location_rounded,
                                  size: 20,
                                ),
                          label: Text(
                            _buscandoLocalizacao
                                ? 'Obtendo localização…'
                                : 'Usar minha localização',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            foregroundColor: diPertinRoxo,
                            backgroundColor:
                                diPertinRoxo.withValues(alpha: 0.1),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _ruaC,
                          label: 'Rua ou avenida',
                          icon: Icons.signpost_outlined,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 1,
                              child: _buildTextField(
                                controller: _numeroC,
                                label: 'Número',
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: _buildTextField(
                                controller: _complementoC,
                                label: 'Apto / casa (opcional)',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _buildTextField(
                          controller: _bairroC,
                          label: 'Bairro',
                          icon: Icons.home_work_outlined,
                        ),
                        const SizedBox(height: 14),
                        _buildTextField(
                          controller: _cidadeC,
                          label: 'Cidade',
                          icon: Icons.location_city_outlined,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _salvando ? null : _salvarPerfil,
                    style: FilledButton.styleFrom(
                      backgroundColor: diPertinLaranja,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          diPertinLaranja.withValues(alpha: 0.5),
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _salvando
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Salvar alterações',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              letterSpacing: -0.2,
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.words,
    List<TextInputFormatter>? inputFormatters,
    bool readOnly = false,
  }) {
    const double radius = 12;
    final Color fill =
        readOnly ? const Color(0xFFF8F7FA) : Colors.white;
    final OutlineInputBorder borderBase = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: const BorderSide(color: Color(0xFFE0DEE8)),
    );

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      readOnly: readOnly,
      inputFormatters: inputFormatters,
      style: TextStyle(
        color: readOnly ? Colors.grey.shade800 : const Color(0xFF1A1A2E),
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: Colors.grey.shade700,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: const TextStyle(
          color: diPertinRoxo,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: icon != null
            ? Icon(icon, color: diPertinRoxo.withValues(alpha: 0.9), size: 22)
            : null,
        filled: true,
        fillColor: fill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        enabledBorder: borderBase,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: diPertinLaranja, width: 2),
        ),
        disabledBorder: borderBase,
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: Colors.red.shade300),
        ),
      ),
    );
  }
}

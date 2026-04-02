// Arquivo: lib/screens/comum/edit_profile_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
// === NOVOS PACOTES PARA A FOTO ===
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../services/location_service.dart';

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
  final TextEditingController _ruaC = TextEditingController();
  final TextEditingController _numeroC = TextEditingController();
  final TextEditingController _bairroC = TextEditingController();
  final TextEditingController _cidadeC = TextEditingController();
  final TextEditingController _complementoC = TextEditingController();

  bool _salvando = false;
  bool _buscandoLocalizacao = false;
  bool _carregandoDados = true;
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
                  "Escolher foto do perfil",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: diPertinRoxo,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera, color: diPertinLaranja),
                title: const Text('Tirar Foto Agora'),
                onTap: () {
                  Navigator.pop(context);
                  _escolherImagem(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: diPertinLaranja,
                ),
                title: const Text('Escolher da Galeria'),
                onTap: () {
                  Navigator.pop(context);
                  _escolherImagem(ImageSource.gallery);
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
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      Placemark place = placemarks[0];
      String cidadeDetectada = place.locality?.isNotEmpty == true
          ? place.locality!
          : (place.subAdministrativeArea?.isNotEmpty == true
                ? place.subAdministrativeArea!
                : (place.administrativeArea ?? ""));

      String? ufDetectado =
          LocationService.extrairUf(place.administrativeArea);

      setState(() {
        _ruaC.text = place.thoroughfare ?? place.street ?? "";
        _bairroC.text = place.subLocality ?? "";
        _cidadeC.text = cidadeDetectada;
        _numeroC.text = place.subThoroughfare ?? "";
        _ufCapturado = ufDetectado?.toUpperCase() ?? '';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📍 Localização capturada! Revise os dados.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro no GPS. Digite manualmente.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _buscandoLocalizacao = false);
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

        Map<String, dynamic> dadosParaSalvar = {
          'nome': _nomeController.text.trim(),
          'endereco_entrega_padrao': enderecoCompleto,
          'cidade': cidadeFinal,
          'foto_perfil': linkDaFoto,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Editar Perfil",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: diPertinRoxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _carregandoDados
          ? const Center(child: CircularProgressIndicator(color: diPertinRoxo))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // === ÁREA DA FOTO DE PERFIL ===
                  Center(
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: diPertinRoxo.withOpacity(0.1),
                            // Mostra a foto escolhida, ou a foto do banco, ou o ícone padrão
                            backgroundImage: _imagemSelecionada != null
                                ? FileImage(_imagemSelecionada!)
                                : (_urlFotoAtual.isNotEmpty
                                          ? NetworkImage(_urlFotoAtual)
                                          : null)
                                      as ImageProvider?,
                            child:
                                (_imagemSelecionada == null &&
                                    _urlFotoAtual.isEmpty)
                                ? const Icon(
                                    Icons.person,
                                    size: 60,
                                    color: diPertinRoxo,
                                  )
                                : null,
                          ),
                        ),
                        // Botãozinho de Câmera em cima da foto
                        GestureDetector(
                          onTap: _mostrarMenuDeFoto,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: diPertinLaranja,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),

                  const Text(
                    "Dados Pessoais",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: diPertinRoxo,
                    ),
                  ),
                  const SizedBox(height: 15),

                  _buildTextField(
                    controller: _nomeController,
                    label: "Seu Nome Completo",
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 25),

                  const Text(
                    "Endereço de Entrega Padrão",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: diPertinRoxo,
                    ),
                  ),
                  const SizedBox(height: 10),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _buscandoLocalizacao
                          ? null
                          : _obterLocalizacaoAtual,
                      icon: _buscandoLocalizacao
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: diPertinLaranja,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.gps_fixed, color: diPertinLaranja),
                      label: Text(
                        _buscandoLocalizacao
                            ? "Buscando pelo GPS..."
                            : "Preencher com GPS",
                        style: const TextStyle(
                          color: diPertinLaranja,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  _buildTextField(
                    controller: _ruaC,
                    label: "Rua / Avenida",
                    icon: Icons.signpost,
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: _buildTextField(
                          controller: _numeroC,
                          label: "Número",
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        flex: 2,
                        child: _buildTextField(
                          controller: _complementoC,
                          label: "Apto/Casa (Opcional)",
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  _buildTextField(
                    controller: _bairroC,
                    label: "Bairro",
                    icon: Icons.home_work,
                  ),
                  const SizedBox(height: 15),
                  _buildTextField(
                    controller: _cidadeC,
                    label: "Cidade",
                    icon: Icons.location_city,
                  ),

                  const SizedBox(height: 40),

                  ElevatedButton(
                    onPressed: _salvando ? null : _salvarPerfil,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: diPertinLaranja,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _salvando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            "SALVAR DADOS",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  // Helper para padronizar os campos (AGORA COM LETRA MAIÚSCULA AUTOMÁTICA)
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    TextInputType keyboardType = TextInputType.text,
    // Adicionamos a capitalização padrão por palavras
    TextCapitalization textCapitalization = TextCapitalization.words,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization, // <--- A MÁGICA ACONTECE AQUI
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null
            ? Icon(icon, color: diPertinRoxo, size: 20)
            : null,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

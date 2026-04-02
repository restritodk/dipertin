// Arquivo: lib/screens/address_screen.dart

import 'package:flutter/material.dart';
// Pacotes para localização
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
// Pacotes para salvar no perfil do usuário
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/location_service.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class AddressScreen extends StatefulWidget {
  const AddressScreen({super.key});

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> {
  bool _buscandoGps = false;
  bool _salvandoNoPerfil = false;
  bool _tornarPadrao = false;
  String _ufCapturado = '';

  final TextEditingController _ruaC = TextEditingController();
  final TextEditingController _numeroC = TextEditingController();
  final TextEditingController _bairroC = TextEditingController();
  final TextEditingController _cidadeC = TextEditingController();
  final TextEditingController _complementoC = TextEditingController();

  @override
  void dispose() {
    // Limpa os controladores para economizar memória
    _ruaC.dispose();
    _numeroC.dispose();
    _bairroC.dispose();
    _cidadeC.dispose();
    _complementoC.dispose();
    super.dispose();
  }

  // Função para capturar o GPS e preencher os campos automaticamente
  Future<void> _obterLocalizacaoAtual() async {
    setState(() => _buscandoGps = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception("Permissão negada");
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];

        String cidadeDetectada =
            place.locality ??
            place.subAdministrativeArea ??
            place.administrativeArea ??
            "";

        String? ufDetectado =
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
                "📍 Endereço preenchido! Revise e adicione o Número.",
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Não conseguimos achar sua localização. Digite manualmente.",
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _buscandoGps = false);
    }
  }

  // LÓGICA TURBINADA PARA SALVAR E RETORNAR
  Future<void> _confirmarEndereco() async {
    // 1. Validação Básica
    if (_ruaC.text.isEmpty ||
        _numeroC.text.isEmpty ||
        _bairroC.text.isEmpty ||
        _cidadeC.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Preencha Rua, Número, Bairro e Cidade!"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    String cidadeFinal = _cidadeC.text.trim();

    // 2. SE FOR PARA TORNAR PADRÃO, SALVA NO PERFIL DO CLIENTE (Firestore)
    if (_tornarPadrao) {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Faça login para salvar um endereço padrão."),
            backgroundColor: diPertinLaranja,
          ),
        );
        return;
      }

      setState(() => _salvandoNoPerfil = true);

      // Cria o mapa do endereço completo
      Map<String, dynamic> enderecoCompleto = {
        'rua': _ruaC.text.trim(),
        'numero': _numeroC.text.trim(),
        'bairro': _bairroC.text.trim(),
        'cidade': cidadeFinal
            .toLowerCase(), // Salva em minúsculo para bater com a Vitrine
        'complemento': _complementoC.text.trim(),
        'data_atualizacao': FieldValue.serverTimestamp(),
      };

      try {
        // Atualiza APENAS o endereço de entrega do cliente no documento dele na coleção users
        // Não toca em nada relacionado a Lojista.
        final Map<String, dynamic> dadosAtualizar = {
          'endereco_entrega_padrao': enderecoCompleto,
          'cidade': cidadeFinal.toLowerCase(),
        };

        if (_ufCapturado.isNotEmpty) {
          dadosAtualizar['uf'] = _ufCapturado;
          dadosAtualizar['cidade_normalizada'] =
              LocationService.normalizar(cidadeFinal);
          dadosAtualizar['uf_normalizado'] =
              LocationService.extrairUf(_ufCapturado) ??
                  LocationService.normalizar(_ufCapturado);
        }

        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update(dadosAtualizar);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Erro ao salvar endereço padrão: $e"),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _salvandoNoPerfil = false);
        return; // Para a execução aqui se der erro
      }
    }

    // 3. RETORNA PARA A VITRINE (Mantendo a compatibilidade existente)
    // Retornamos apenas a cidade, pois é o que a Vitrine usa para filtrar as lojas.
    if (mounted) {
      Navigator.pop(context, cidadeFinal);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Endereço de Entrega",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: diPertinRoxo,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ÁREA DE LOCALIZAÇÃO AUTOMÁTICA
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Icon(Icons.gps_fixed, size: 50, color: diPertinLaranja),
                  const SizedBox(height: 15),
                  const Text(
                    "Usar localização atual",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: diPertinRoxo,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    "Preencheremos os campos abaixo usando seu GPS.",
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 15),
                  ElevatedButton.icon(
                    onPressed: _buscandoGps ? null : _obterLocalizacaoAtual,
                    icon: const Icon(
                      Icons.my_location,
                      color: Colors.white,
                      size: 18,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: diPertinRoxo,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    label: _buscandoGps
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            "Caputar GPS",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      "OU DIGITE MANUALMENTE",
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
            ),

            // CAMPOS MANUAIS
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
                    label: "Apto / Casa (Opcional)",
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

            const SizedBox(height: 15),

            // === NOVO CAMPO: TORNAR PADRÃO ===
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SwitchListTile(
                title: const Text(
                  "Salvar como endereço padrão de entregas",
                  style: TextStyle(
                    fontSize: 14,
                    color: diPertinRoxo,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: const Text(
                  "Sempre usar este local ao abrir o app",
                  style: TextStyle(fontSize: 12),
                ),
                value: _tornarPadrao,
                activeThumbColor: diPertinLaranja,
                onChanged: (bool value) {
                  setState(() {
                    _tornarPadrao = value;
                  });
                },
              ),
            ),

            const SizedBox(height: 40),

            // BOTÃO DE CONFIRMAR
            ElevatedButton(
              onPressed: (_salvandoNoPerfil || _buscandoGps)
                  ? null
                  : _confirmarEndereco,
              style: ElevatedButton.styleFrom(
                backgroundColor: diPertinLaranja,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 3,
              ),
              child: _salvandoNoPerfil
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      "CONFIRMAR ENDEREÇO",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // Helper para criar campos de texto padronizados
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null
            ? Icon(icon, color: diPertinRoxo, size: 20)
            : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        labelStyle: const TextStyle(fontSize: 14, color: Colors.grey),
      ),
    );
  }
}

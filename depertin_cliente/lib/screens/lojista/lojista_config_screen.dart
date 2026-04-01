// Arquivo: lib/screens/lojista/lojista_config_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class LojistaConfigScreen extends StatefulWidget {
  final Map<String, dynamic> dadosAtuaisDaLoja;

  const LojistaConfigScreen({super.key, required this.dadosAtuaisDaLoja});

  @override
  State<LojistaConfigScreen> createState() => _LojistaConfigScreenState();
}

class _LojistaConfigScreenState extends State<LojistaConfigScreen> {
  late TextEditingController _nomeLojaController;
  late TextEditingController _enderecoLojaController;
  late TextEditingController _telefoneController;

  bool _salvando = false;
  bool _buscandoLocalizacao = false;
  bool _pausadoManualmente = false;

  final Map<String, String> _nomesDias = {
    'segunda': 'Segunda',
    'terca': 'Terça',
    'quarta': 'Quarta',
    'quinta': 'Quinta',
    'sexta': 'Sexta',
    'sabado': 'Sábado',
    'domingo': 'Domingo',
  };

  final Map<String, Map<String, dynamic>> _horarios = {
    'segunda': {'ativo': true, 'abre': '08:00', 'fecha': '18:00'},
    'terca': {'ativo': true, 'abre': '08:00', 'fecha': '18:00'},
    'quarta': {'ativo': true, 'abre': '08:00', 'fecha': '18:00'},
    'quinta': {'ativo': true, 'abre': '08:00', 'fecha': '18:00'},
    'sexta': {'ativo': true, 'abre': '08:00', 'fecha': '18:00'},
    'sabado': {'ativo': true, 'abre': '08:00', 'fecha': '12:00'},
    'domingo': {'ativo': false, 'abre': '08:00', 'fecha': '12:00'},
  };

  @override
  void initState() {
    super.initState();
    _nomeLojaController = TextEditingController(
      text:
          widget.dadosAtuaisDaLoja['loja_nome'] ??
          widget.dadosAtuaisDaLoja['nome'] ??
          '',
    );
    _enderecoLojaController = TextEditingController(
      text: widget.dadosAtuaisDaLoja['endereco'] ?? '',
    );
    _telefoneController = TextEditingController(
      text: widget.dadosAtuaisDaLoja['telefone'] ?? '',
    );

    _pausadoManualmente =
        widget.dadosAtuaisDaLoja['pausado_manualmente'] ?? false;

    if (widget.dadosAtuaisDaLoja['horarios'] != null) {
      Map<String, dynamic> hBanco = widget.dadosAtuaisDaLoja['horarios'];
      hBanco.forEach((key, value) {
        if (_horarios.containsKey(key)) {
          _horarios[key] = Map<String, dynamic>.from(value);
        }
      });
    }
  }

  // === NOVA FUNÇÃO: BUSCAR GPS PARA A LOJA ===
  Future<void> _obterLocalizacaoDaLoja() async {
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

      setState(() {
        _enderecoLojaController.text =
            "${place.thoroughfare ?? place.street ?? ''}, ${place.subThoroughfare ?? 'S/N'}, ${place.subLocality ?? ''} - $cidadeDetectada";
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📍 Localização da Loja capturada!'),
            backgroundColor: Colors.green,
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

  Future<void> _salvarConfiguracoes() async {
    if (_enderecoLojaController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A loja precisa ter um endereço de retirada válido.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
              'loja_nome': _nomeLojaController.text.trim(),
              'endereco': _enderecoLojaController.text.trim(),
              'telefone': _telefoneController.text.trim(),
              'pausado_manualmente': _pausadoManualmente,
              'horarios': _horarios,
            });

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Configurações operacionais salvas!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao salvar configurações.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  // Abre o Relógio
  Future<void> _selecionarHora(String chaveDia, bool isAbre) async {
    var config = _horarios[chaveDia]!;
    String horaAtualStr = isAbre ? config['abre'] : config['fecha'];

    int h = int.parse(horaAtualStr.split(':')[0]);
    int m = int.parse(horaAtualStr.split(':')[1]);

    TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: h, minute: m),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: diPertinRoxo),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        String hh = picked.hour.toString().padLeft(2, '0');
        String mm = picked.minute.toString().padLeft(2, '0');
        _horarios[chaveDia]![isAbre ? 'abre' : 'fecha'] = "$hh:$mm";
      });
    }
  }

  Widget _buildLinhaHorario(String chaveDia) {
    var config = _horarios[chaveDia]!;
    bool ativo = config['ativo'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Checkbox(
            value: ativo,
            activeColor: diPertinLaranja,
            onChanged: (val) =>
                setState(() => _horarios[chaveDia]!['ativo'] = val),
          ),
          SizedBox(
            width: 80,
            child: Text(
              _nomesDias[chaveDia]!,
              style: TextStyle(
                fontWeight: ativo ? FontWeight.bold : FontWeight.normal,
                color: ativo ? Colors.black : Colors.grey,
              ),
            ),
          ),
          if (ativo) ...[
            Expanded(
              child: InkWell(
                onTap: () => _selecionarHora(chaveDia, true),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    config['abre'],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text("às"),
            ),
            Expanded(
              child: InkWell(
                onTap: () => _selecionarHora(chaveDia, false),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    config['fecha'],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ] else
            const Expanded(
              child: Text(
                "FECHADO",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Configuração Operacional",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: diPertinRoxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Dados Comerciais",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: diPertinRoxo,
              ),
            ),
            const SizedBox(height: 15),

            TextField(
              controller: _nomeLojaController,
              decoration: const InputDecoration(
                labelText: "Nome da Loja",
                prefixIcon: Icon(Icons.storefront, color: diPertinLaranja),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),

            TextField(
              controller: _telefoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: "Telefone / WhatsApp",
                prefixIcon: Icon(Icons.phone, color: diPertinLaranja),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),

            // === ENDEREÇO COM BOTÃO GPS ===
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Endereço Físico (Retirada)",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: _buscandoLocalizacao
                      ? null
                      : _obterLocalizacaoDaLoja,
                  icon: _buscandoLocalizacao
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            color: diPertinLaranja,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.my_location,
                          size: 16,
                          color: diPertinLaranja,
                        ),
                  label: const Text(
                    "Usar GPS",
                    style: TextStyle(color: diPertinLaranja, fontSize: 12),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _enderecoLojaController,
              decoration: const InputDecoration(
                hintText: "Rua, Número, Bairro, Cidade",
                prefixIcon: Icon(Icons.location_on, color: Colors.red),
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8.0, left: 5),
              child: Text(
                "* Este é o endereço que o Waze do entregador vai usar para buscar a mercadoria.",
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),

            const SizedBox(height: 30),
            const Divider(),
            const SizedBox(height: 10),

            const Text(
              "Controle de Operação",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: diPertinRoxo,
              ),
            ),
            const SizedBox(height: 15),

            Container(
              decoration: BoxDecoration(
                color: _pausadoManualmente ? Colors.red[50] : Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _pausadoManualmente ? Colors.red : Colors.grey[300]!,
                ),
              ),
              child: SwitchListTile(
                title: Text(
                  "Pausar Loja Agora",
                  style: TextStyle(
                    color: _pausadoManualmente ? Colors.red : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  "Fecha a loja na vitrine imediatamente (chuva, falta de luz, etc).",
                  style: TextStyle(fontSize: 11),
                ),
                value: _pausadoManualmente,
                activeThumbColor: Colors.red,
                onChanged: (val) => setState(() => _pausadoManualmente = val),
              ),
            ),
            const SizedBox(height: 25),

            const Text(
              "Grade de Horários:",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  'domingo',
                  'segunda',
                  'terca',
                  'quarta',
                  'quinta',
                  'sexta',
                  'sabado',
                ].map((dia) => _buildLinhaHorario(dia)).toList(),
              ),
            ),

            const SizedBox(height: 30),

            ElevatedButton(
              onPressed: _salvando ? null : _salvarConfiguracoes,
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
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : const Text(
                      "SALVAR CONFIGURAÇÕES",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

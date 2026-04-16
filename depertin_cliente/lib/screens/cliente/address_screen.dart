// Arquivo: lib/screens/address_screen.dart

import 'package:flutter/material.dart';
// Pacotes para localização
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
// Pacotes para salvar no perfil do usuário
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/location_service.dart';
import '../../services/permissoes_app_service.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class AddressScreen extends StatefulWidget {
  const AddressScreen({
    super.key,
    this.modoCadastroLista = false,
    this.enderecoDocumentId,
    this.dadosIniciais,
    this.apenasAtualizarPerfilPadrao = false,
    this.tornarPadraoInicial,
  });

  /// Se `true`, salva em `users/{uid}/enderecos` e opcionalmente atualiza o padrão de entrega.
  /// Se `false`, mantém o fluxo original (ex.: retorno de cidade para a vitrine).
  final bool modoCadastroLista;

  /// Edição: ID do documento em `users/{uid}/enderecos/{id}`.
  final String? enderecoDocumentId;

  /// Pré-preenche os campos (novo ou edição).
  final Map<String, dynamic>? dadosIniciais;

  /// Só atualiza `endereco_entrega_padrao` no perfil (sem subcoleção) — ex.: editar card “Padrão”.
  final bool apenasAtualizarPerfilPadrao;

  /// Estado inicial do switch “padrão” (ex.: edição de um endereço que já é o padrão).
  final bool? tornarPadraoInicial;

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> {
  bool _buscandoGps = false;
  bool _salvandoNoPerfil = false;
  late bool _tornarPadrao;

  final TextEditingController _ruaC = TextEditingController();
  final TextEditingController _numeroC = TextEditingController();
  final TextEditingController _bairroC = TextEditingController();
  final TextEditingController _cidadeC = TextEditingController();
  final TextEditingController _estadoC = TextEditingController();
  final TextEditingController _complementoC = TextEditingController();

  @override
  void initState() {
    super.initState();
    final d = widget.dadosIniciais;
    if (d != null) {
      _ruaC.text = (d['rua'] ?? '').toString().trim();
      _numeroC.text = (d['numero'] ?? '').toString().trim();
      _bairroC.text = (d['bairro'] ?? '').toString().trim();
      _cidadeC.text = (d['cidade'] ?? '').toString().trim();
      _estadoC.text =
          (d['estado'] ?? d['uf'] ?? '').toString().trim().toUpperCase();
      _complementoC.text = (d['complemento'] ?? '').toString().trim();
    }
    if (widget.tornarPadraoInicial != null) {
      _tornarPadrao = widget.tornarPadraoInicial!;
    } else if (widget.apenasAtualizarPerfilPadrao) {
      _tornarPadrao = true;
    } else {
      _tornarPadrao = false;
    }
  }

  @override
  void dispose() {
    // Limpa os controladores para economizar memória
    _ruaC.dispose();
    _numeroC.dispose();
    _bairroC.dispose();
    _cidadeC.dispose();
    _estadoC.dispose();
    _complementoC.dispose();
    super.dispose();
  }

  // Função para capturar o GPS e preencher os campos automaticamente
  Future<void> _obterLocalizacaoAtual() async {
    setState(() => _buscandoGps = true);

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

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final Placemark base = placemarks.first;
        final Map<String, String> linhas =
            LocationService.linhasEnderecoDoPlacemark(base);
        final ({String cidade, String uf})? regiao =
            LocationService.resolverCidadeUfDePlacemarks(placemarks);

        String cidadeFinal = regiao?.cidade ?? '';
        if (cidadeFinal.isEmpty) {
          cidadeFinal = base.locality ??
              base.subAdministrativeArea ??
              base.administrativeArea ??
              '';
        }
        String ufFinal = regiao?.uf ?? '';
        if (ufFinal.isEmpty) {
          final u = LocationService.ufDoPlacemark(base);
          ufFinal = u?.toUpperCase() ?? '';
        }

        setState(() {
          _ruaC.text = linhas['rua'] ?? '';
          _numeroC.text = linhas['numero'] ?? '';
          _bairroC.text = linhas['bairro'] ?? '';
          _cidadeC.text = cidadeFinal;
          _estadoC.text = ufFinal;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Endereço preenchido pelo GPS. Confira rua, número e bairro.',
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não conseguimos obter a localização. Digite manualmente.',
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
    if (_salvandoNoPerfil) return;

    // 1. Validação Básica
    if (_ruaC.text.isEmpty ||
        _numeroC.text.isEmpty ||
        _bairroC.text.isEmpty ||
        _cidadeC.text.isEmpty ||
        _estadoC.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Preencha Rua, Número, Bairro, Cidade e Estado (UF).',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    String cidadeFinal = _cidadeC.text.trim();

    // Modo Configurações → lista de endereços (subcoleção + opcional padrão)
    if (widget.modoCadastroLista || widget.apenasAtualizarPerfilPadrao) {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Faça login para salvar o endereço.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() => _salvandoNoPerfil = true);

      final String estadoUf = _estadoC.text.trim().toUpperCase();

      Map<String, dynamic> enderecoCompleto = {
        'rua': _ruaC.text.trim(),
        'numero': _numeroC.text.trim(),
        'bairro': _bairroC.text.trim(),
        'cidade': cidadeFinal.toLowerCase(),
        'estado': estadoUf,
        'complemento': _complementoC.text.trim(),
        'data_atualizacao': FieldValue.serverTimestamp(),
      };

      Future<void> aplicarPadraoNoPerfil() async {
        final Map<String, dynamic> dadosAtualizar = {
          'endereco_entrega_padrao': enderecoCompleto,
          'cidade': cidadeFinal.toLowerCase(),
          'onboarding_endereco_pendente': false,
          'onboarding_endereco_concluido_em': FieldValue.serverTimestamp(),
        };
        if (estadoUf.isNotEmpty) {
          dadosAtualizar['uf'] = estadoUf;
          dadosAtualizar['cidade_normalizada'] =
              LocationService.normalizar(cidadeFinal);
          dadosAtualizar['uf_normalizado'] =
              LocationService.extrairUf(estadoUf) ??
                  LocationService.normalizar(estadoUf);
        }
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update(dadosAtualizar);
      }

      Future<void> marcarOnboardingConcluido() async {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
          'onboarding_endereco_pendente': false,
          'onboarding_endereco_concluido_em': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      try {
        if (widget.apenasAtualizarPerfilPadrao) {
          await aplicarPadraoNoPerfil();
        } else if (widget.enderecoDocumentId != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('enderecos')
              .doc(widget.enderecoDocumentId)
              .update(enderecoCompleto);
          if (_tornarPadrao) {
            await aplicarPadraoNoPerfil();
          } else {
            await marcarOnboardingConcluido();
          }
        } else if (_tornarPadrao) {
          // Só padrão no perfil: evita duplicar o mesmo endereço na lista + card “Padrão”.
          await aplicarPadraoNoPerfil();
        } else {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('enderecos')
              .add({
            ...enderecoCompleto,
            'criado_em': FieldValue.serverTimestamp(),
          });
          await marcarOnboardingConcluido();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Endereço salvo com sucesso.'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pop(context, true);
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
        if (mounted) setState(() => _salvandoNoPerfil = false);
      }
      return;
    }

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
      final String estadoUf = _estadoC.text.trim().toUpperCase();

      Map<String, dynamic> enderecoCompleto = {
        'rua': _ruaC.text.trim(),
        'numero': _numeroC.text.trim(),
        'bairro': _bairroC.text.trim(),
        'cidade': cidadeFinal
            .toLowerCase(), // Salva em minúsculo para bater com a Vitrine
        'estado': estadoUf,
        'complemento': _complementoC.text.trim(),
        'data_atualizacao': FieldValue.serverTimestamp(),
      };

      try {
        // Atualiza APENAS o endereço de entrega do cliente no documento dele na coleção users
        // Não toca em nada relacionado a Lojista.
        final Map<String, dynamic> dadosAtualizar = {
          'endereco_entrega_padrao': enderecoCompleto,
          'cidade': cidadeFinal.toLowerCase(),
          'onboarding_endereco_pendente': false,
          'onboarding_endereco_concluido_em': FieldValue.serverTimestamp(),
        };

        if (estadoUf.isNotEmpty) {
          dadosAtualizar['uf'] = estadoUf;
          dadosAtualizar['cidade_normalizada'] =
              LocationService.normalizar(cidadeFinal);
          dadosAtualizar['uf_normalizado'] =
              LocationService.extrairUf(estadoUf) ??
                  LocationService.normalizar(estadoUf);
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
        title: Text(
          widget.apenasAtualizarPerfilPadrao
              ? 'Endereço padrão'
              : (widget.enderecoDocumentId != null
                  ? 'Editar endereço'
                  : (widget.modoCadastroLista
                      ? 'Novo endereço'
                      : 'Endereço de Entrega')),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                            "Capturar GPS",
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _buildTextField(
                    controller: _cidadeC,
                    label: "Cidade",
                    icon: Icons.location_city,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  flex: 1,
                  child: _buildTextField(
                    controller: _estadoC,
                    label: "UF",
                    icon: Icons.map,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 15),

            // === TORNAR PADRÃO (não exibe no modo “só perfil padrão”) ===
            if (!widget.apenasAtualizarPerfilPadrao)
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

            if (!widget.apenasAtualizarPerfilPadrao) const SizedBox(height: 40),
            if (widget.apenasAtualizarPerfilPadrao) const SizedBox(height: 24),

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

// Arquivo: lib/screens/address_screen.dart

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Pacotes para localização
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
// Pacotes para salvar no perfil do usuário
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/location_service.dart';
import '../../widgets/dipertin_scroll_body.dart';
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
  bool _buscandoCep = false;
  bool _salvandoNoPerfil = false;
  late bool _tornarPadrao;

  final TextEditingController _cepC = TextEditingController();
  final TextEditingController _ruaC = TextEditingController();
  final TextEditingController _numeroC = TextEditingController();
  final TextEditingController _bairroC = TextEditingController();
  final TextEditingController _cidadeC = TextEditingController();
  final TextEditingController _estadoC = TextEditingController();
  final TextEditingController _complementoC = TextEditingController();

  final FocusNode _numeroFocus = FocusNode();

  /// Último CEP (8 dígitos) já consultado, para não repetir a chamada à API.
  String _ultimoCepBuscado = '';

  @override
  void initState() {
    super.initState();
    final d = widget.dadosIniciais;
    if (d != null) {
      _cepC.text = _formatarCep((d['cep'] ?? '').toString());
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
    _cepC.dispose();
    _ruaC.dispose();
    _numeroC.dispose();
    _bairroC.dispose();
    _cidadeC.dispose();
    _estadoC.dispose();
    _complementoC.dispose();
    _numeroFocus.dispose();
    super.dispose();
  }

  static String _apenasDigitos(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// Formata para `00000-000` (aceita entrada com ou sem máscara).
  static String _formatarCep(String s) {
    final d = _apenasDigitos(s);
    if (d.length <= 5) return d;
    final corte = d.length > 8 ? 8 : d.length;
    return '${d.substring(0, 5)}-${d.substring(5, corte)}';
  }

  /// Coloca o foco no campo Número após um preenchimento automático,
  /// já que é o único dado que o cliente precisa digitar.
  void _focarNumero() {
    if (!mounted) return;
    FocusScope.of(context).requestFocus(_numeroFocus);
  }

  // Função para capturar o GPS e preencher os campos automaticamente.
  // Mobile usa o plugin `geocoding`; na web usa reverse geocoding via Nominatim
  // (o plugin `geocoding` não funciona no navegador).
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
      ).timeout(const Duration(seconds: 18));

      _EnderecoPreenchido? preenchido;

      if (kIsWeb) {
        preenchido = await _reverseGeocodeWebNominatim(
          position.latitude,
          position.longitude,
        );
      } else {
        final List<Placemark> placemarks = await placemarkFromCoordinates(
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
            ufFinal = LocationService.ufDoPlacemark(base)?.toUpperCase() ?? '';
          }

          preenchido = _EnderecoPreenchido(
            rua: linhas['rua'] ?? '',
            bairro: linhas['bairro'] ?? '',
            cidade: cidadeFinal,
            uf: ufFinal,
            cep: (base.postalCode ?? '').trim(),
          );
        }
      }

      if (!mounted) return;

      if (preenchido != null && preenchido.temAlgo) {
        _aplicarEnderecoPreenchido(preenchido);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Endereço preenchido pela localização. Confira e informe o número.',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não localizamos o endereço pelo GPS. Use o CEP ou digite manualmente.',
            ),
            backgroundColor: diPertinLaranja,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não conseguimos obter a localização. Use o CEP ou digite manualmente.',
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _buscandoGps = false);
    }
  }

  /// Reverse geocoding no navegador (web) via Nominatim (OSM).
  Future<_EnderecoPreenchido?> _reverseGeocodeWebNominatim(
    double lat,
    double lng,
  ) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng'
        '&format=json&addressdetails=1&accept-language=pt-BR',
      );
      final res = await http.get(
        uri,
        headers: const {
          'User-Agent': 'DiPertinCliente/1.0 (https://depertin.app)',
          'Accept-Language': 'pt-BR,pt;q=0.9',
        },
      ).timeout(const Duration(seconds: 14));
      if (res.statusCode != 200) return null;
      final data =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final addr = data['address'] as Map<String, dynamic>?;
      if (addr == null) return null;

      String texto(List<String> chaves) {
        for (final k in chaves) {
          final v = addr[k]?.toString().trim();
          if (v != null && v.isNotEmpty) return v;
        }
        return '';
      }

      final cidade = texto(['city', 'town', 'village', 'municipality']);
      String uf = LocationService.extrairUf(addr['state']?.toString()) ?? '';
      if (uf.isEmpty) {
        final iso = addr['ISO3166-2-lvl4']?.toString() ?? '';
        final m = RegExp(r'^BR-([A-Za-z]{2})$').firstMatch(iso);
        if (m != null) uf = m.group(1)!;
      }

      return _EnderecoPreenchido(
        rua: texto(['road', 'pedestrian', 'footway']),
        bairro: texto(['suburb', 'neighbourhood', 'city_district']),
        cidade: cidade,
        uf: uf.toUpperCase(),
        cep: texto(['postcode']),
      );
    } catch (e) {
      debugPrint('[AddressScreen] Nominatim (web): $e');
      return null;
    }
  }

  /// Busca o endereço pelo CEP usando a API pública ViaCEP (todas as plataformas).
  Future<void> _buscarPorCep({bool silencioso = false}) async {
    final cep = _apenasDigitos(_cepC.text);
    if (cep.length != 8) {
      if (!silencioso && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Digite um CEP válido com 8 dígitos.'),
            backgroundColor: diPertinLaranja,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (_buscandoCep) return;
    _ultimoCepBuscado = cep;

    setState(() => _buscandoCep = true);
    try {
      final res = await http
          .get(Uri.parse('https://viacep.com.br/ws/$cep/json/'))
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;

      if (res.statusCode != 200) {
        throw Exception('status ${res.statusCode}');
      }
      final data =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;

      if (data['erro'] == true || data['erro'] == 'true') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('CEP não encontrado. Confira ou digite manualmente.'),
            backgroundColor: diPertinLaranja,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      _aplicarEnderecoPreenchido(
        _EnderecoPreenchido(
          rua: (data['logradouro'] ?? '').toString().trim(),
          bairro: (data['bairro'] ?? '').toString().trim(),
          cidade: (data['localidade'] ?? '').toString().trim(),
          uf: (data['uf'] ?? '').toString().trim().toUpperCase(),
          cep: cep,
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Endereço encontrado. Agora é só informar o número.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted && !silencioso) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível buscar o CEP. Verifique a conexão ou digite manualmente.',
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _buscandoCep = false);
    }
  }

  /// Preenche os campos a partir de um endereço resolvido (GPS ou CEP),
  /// mantendo o foco no campo Número — único dado que falta ao cliente.
  void _aplicarEnderecoPreenchido(_EnderecoPreenchido e) {
    setState(() {
      if (e.cep.isNotEmpty) _cepC.text = _formatarCep(e.cep);
      if (e.rua.isNotEmpty) _ruaC.text = e.rua;
      if (e.bairro.isNotEmpty) _bairroC.text = e.bairro;
      if (e.cidade.isNotEmpty) _cidadeC.text = e.cidade;
      if (e.uf.isNotEmpty) _estadoC.text = e.uf;
      // Número nunca vem da API/GPS de forma confiável: o cliente informa.
      _numeroC.clear();
    });
    _focarNumero();
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
        'cep': _apenasDigitos(_cepC.text),
        'rua': _ruaC.text.trim(),
        'numero': _numeroC.text.trim(),
        'bairro': _bairroC.text.trim(),
        'cidade': cidadeFinal.toLowerCase(),
        'estado': estadoUf,
        'complemento': _complementoC.text.trim(),
        'data_atualizacao': FieldValue.serverTimestamp(),
      };

      Future<void> aplicarPadraoNoPerfil() async {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'endereco_entrega_padrao': enderecoCompleto,
          'onboarding_endereco_pendente': false,
          'onboarding_endereco_concluido_em': FieldValue.serverTimestamp(),
        });
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
        'cep': _apenasDigitos(_cepC.text),
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
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'endereco_entrega_padrao': enderecoCompleto,
          'onboarding_endereco_pendente': false,
          'onboarding_endereco_concluido_em': FieldValue.serverTimestamp(),
        });
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
      body: DiPertinScrollBody(
        padding: const EdgeInsets.all(20),
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

            // CAMPO CEP (autocompleta o endereço via ViaCEP)
            _buildTextField(
              controller: _cepC,
              label: "CEP",
              icon: Icons.local_post_office,
              keyboardType: TextInputType.number,
              maxLength: 9,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                _CepInputFormatter(),
              ],
              onChanged: (valor) {
                final d = _apenasDigitos(valor);
                // Permite uma nova busca caso o cliente apague e redigite.
                if (d.length < 8) {
                  _ultimoCepBuscado = '';
                  return;
                }
                if (d.length == 8 && d != _ultimoCepBuscado) {
                  // Ao completar o 8º dígito, busca automaticamente e
                  // fecha o teclado para destacar o campo Número.
                  FocusScope.of(context).unfocus();
                  _buscarPorCep(silencioso: true);
                }
              },
              onSubmitted: (_) => _buscarPorCep(),
              suffixIcon: _buscandoCep
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: diPertinRoxo,
                        ),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Buscar CEP',
                      icon: const Icon(Icons.search, color: diPertinRoxo),
                      onPressed: _buscandoCep ? null : () => _buscarPorCep(),
                    ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 4, top: 6, bottom: 10),
              child: Text(
                "Digite o CEP e preencheremos o endereço. Depois é só informar o número.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 5),

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
                    focusNode: _numeroFocus,
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
    FocusNode? focusNode,
    Widget? suffixIcon,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        prefixIcon: icon != null
            ? Icon(icon, color: diPertinRoxo, size: 20)
            : null,
        suffixIcon: suffixIcon,
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

/// Endereço resolvido por GPS ou CEP. O número nunca é considerado confiável.
class _EnderecoPreenchido {
  const _EnderecoPreenchido({
    this.rua = '',
    this.bairro = '',
    this.cidade = '',
    this.uf = '',
    this.cep = '',
  });

  final String rua;
  final String bairro;
  final String cidade;
  final String uf;
  final String cep;

  bool get temAlgo =>
      rua.isNotEmpty ||
      bairro.isNotEmpty ||
      cidade.isNotEmpty ||
      uf.isNotEmpty ||
      cep.isNotEmpty;
}

/// Aplica máscara `00000-000` ao CEP conforme o usuário digita.
class _CepInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final corte = digits.length > 8 ? 8 : digits.length;
    final limpos = digits.substring(0, corte);
    final buffer = StringBuffer();
    for (var i = 0; i < limpos.length; i++) {
      if (i == 5) buffer.write('-');
      buffer.write(limpos[i]);
    }
    final texto = buffer.toString();
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

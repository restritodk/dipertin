import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum LocationStatus {
  desconhecido,
  pronto,
  servicoDesativado,
  permissaoNegada,
  permissaoNegadaPermanente,
}

/// Localização do usuário exposta ao app: apenas **cidade** e **UF**, normalizados.
/// Coordenadas ficam encapsuladas só para leitura GPS e geocodificação reversa.
class LocationService extends ChangeNotifier {
  LocationStatus _status = LocationStatus.desconhecido;
  bool _initialized = false;
  StreamSubscription<ServiceStatus>? _serviceSubscription;
  StreamSubscription<Position>? _positionSubscription;

  String? _cidadeDetectada;
  String? _ufDetectado;
  String _cidadeNormalizada = '';
  String _ufNormalizado = '';
  double? _ultimaLat;
  double? _ultimaLng;
  bool _detectandoCidade = false;

  /// Só fica true após uma detecção bem-sucedida **nesta execução** (não basta cache em disco).
  bool _deteccaoSessaoConfirmada = false;

  LocationStatus get status => _status;
  bool get initialized => _initialized;
  String? get cidadeDetectada => _cidadeDetectada;
  String? get ufDetectado => _ufDetectado;
  String get cidadeNormalizada => _cidadeNormalizada;
  String get ufNormalizado => _ufNormalizado;
  bool get detectandoCidade => _detectandoCidade;

  bool get cidadePronta =>
      _deteccaoSessaoConfirmada &&
      _cidadeNormalizada.isNotEmpty &&
      _ufNormalizado.isNotEmpty;

  String get cidadeExibicao {
    if (_cidadeDetectada == null || _ufDetectado == null) return '';
    return '$_cidadeDetectada - $_ufDetectado';
  }

  static const String _chaveCidade = 'cidade_vitrine';
  static const String _chaveUf = 'uf_vitrine';
  static const String _chaveCidadeNorm = 'cidade_vitrine_norm';
  static const String _chaveUfNorm = 'uf_vitrine_norm';

  static const Map<String, String> _estadoParaUf = {
    'acre': 'ac',
    'alagoas': 'al',
    'amapá': 'ap',
    'amapa': 'ap',
    'amazonas': 'am',
    'bahia': 'ba',
    'ceará': 'ce',
    'ceara': 'ce',
    'distrito federal': 'df',
    'espírito santo': 'es',
    'espirito santo': 'es',
    'goiás': 'go',
    'goias': 'go',
    'maranhão': 'ma',
    'maranhao': 'ma',
    'mato grosso': 'mt',
    'mato grosso do sul': 'ms',
    'minas gerais': 'mg',
    'pará': 'pa',
    'para': 'pa',
    'paraíba': 'pb',
    'paraiba': 'pb',
    'paraná': 'pr',
    'parana': 'pr',
    'pernambuco': 'pe',
    'piauí': 'pi',
    'piaui': 'pi',
    'rio de janeiro': 'rj',
    'rio grande do norte': 'rn',
    'rio grande do sul': 'rs',
    'rondônia': 'ro',
    'rondonia': 'ro',
    'roraima': 'rr',
    'santa catarina': 'sc',
    'são paulo': 'sp',
    'sao paulo': 'sp',
    'sergipe': 'se',
    'tocantins': 'to',
    'ac': 'ac',
    'al': 'al',
    'ap': 'ap',
    'am': 'am',
    'ba': 'ba',
    'ce': 'ce',
    'df': 'df',
    'es': 'es',
    'go': 'go',
    'ma': 'ma',
    'mt': 'mt',
    'ms': 'ms',
    'mg': 'mg',
    'pa': 'pa',
    'pb': 'pb',
    'pr': 'pr',
    'pe': 'pe',
    'pi': 'pi',
    'rj': 'rj',
    'rn': 'rn',
    'rs': 'rs',
    'ro': 'ro',
    'rr': 'rr',
    'sc': 'sc',
    'sp': 'sp',
    'se': 'se',
    'to': 'to',
  };

  static const Set<String> _nomesEstadosCompletos = {
    'acre',
    'alagoas',
    'amapá',
    'amapa',
    'amazonas',
    'bahia',
    'ceará',
    'ceara',
    'distrito federal',
    'espírito santo',
    'espirito santo',
    'goiás',
    'goias',
    'maranhão',
    'maranhao',
    'mato grosso',
    'mato grosso do sul',
    'minas gerais',
    'pará',
    'para',
    'paraíba',
    'paraiba',
    'paraná',
    'parana',
    'pernambuco',
    'piauí',
    'piaui',
    'rio de janeiro',
    'rio grande do norte',
    'rio grande do sul',
    'rondônia',
    'rondonia',
    'roraima',
    'santa catarina',
    'são paulo',
    'sao paulo',
    'sergipe',
    'tocantins',
  };

  static String normalizar(String texto) =>
      texto.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Remove acentos (á→a, ô→o, ç→c, …) mantendo o restante do texto.
  /// Usado **somente** na comparação de cidade do comparador de anúncios,
  /// porque o painel web grava `cidade_normalizada` sem acentos
  /// (ex.: `"rondonopolis — mt"`), enquanto o app detecta a cidade do GPS
  /// preservando acentos (ex.: `"rondonópolis"`). Sem esse ajuste, o match
  /// falha para cidades com acento no nome (Rondonópolis, Goiânia, …).
  static String _removerAcentos(String s) {
    const com = 'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ';
    const sem = 'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN';
    final buf = StringBuffer();
    for (final ch in s.split('')) {
      final i = com.indexOf(ch);
      buf.write(i >= 0 ? sem[i] : ch);
    }
    return buf.toString();
  }

  /// Chave canônica para comparar nomes de cidade entre documentos salvos
  /// pelo painel web (sem acentos) e pela cidade detectada do usuário
  /// (com acentos). Aplica `normalizar` + remoção de acentos.
  static String _chaveCidadeComparacao(String s) =>
      _removerAcentos(normalizar(s));

  static String? extrairUf(String? estado) {
    if (estado == null || estado.trim().isEmpty) return null;
    final t = estado.trim();
    final n = normalizar(t);
    if (t.length == 2 && _estadoParaUf[n] != null) return _estadoParaUf[n];
    return _estadoParaUf[n];
  }

  /// Painel pode gravar [campoCidade] como `"Município — UF"` (IBGE). O app só
  /// compara o nome do município com [cidadeNormalizada]; se houver UF no texto,
  /// ela também deve bater com [ufNormalizado].
  static String nomeCidadeParaFiltroAnuncio(String? campoCidade) {
    if (campoCidade == null || campoCidade.trim().isEmpty) return '';
    final t = campoCidade.trim();
    final partes = t.split(RegExp(r'\s*[—–\-]\s*'));
    final nome = partes.isNotEmpty ? partes.first.trim() : t;
    return normalizar(nome);
  }

  /// Sigla (minúsculas) após `—` / `-`, ou null se o campo for só o nome.
  static String? ufAnuncioOpcional(String? campoCidade) {
    if (campoCidade == null || campoCidade.trim().isEmpty) return null;
    final t = campoCidade.trim();
    final partes = t.split(RegExp(r'\s*[—–\-]\s*'));
    if (partes.length < 2) return null;
    final ult = partes.last.trim();
    if (ult.length == 2) return ult.toLowerCase();
    return extrairUf(ult)?.toLowerCase();
  }

  static bool cidadeCampoCorrespondeUsuario({
    required String? campoCidade,
    required String cidadeNormUsuario,
    required String ufNormUsuario,
    bool globalSeVazio = false,
  }) {
    final raw = (campoCidade ?? '').toString().trim();
    if (raw.isEmpty) return globalSeVazio;
    final nome = nomeCidadeParaFiltroAnuncio(raw);
    if (nome.isEmpty) return globalSeVazio;
    // Tolerante a acentos: o painel web grava `cidade_normalizada` sem
    // acentos, o app detecta cidade do GPS com acentos. Comparar só por
    // lowercase faria `rondonopolis != rondonópolis` e o anúncio sumir.
    if (_chaveCidadeComparacao(nome) !=
        _chaveCidadeComparacao(cidadeNormUsuario)) return false;
    final ufAd = ufAnuncioOpcional(raw);
    if (ufAd != null &&
        ufAd.isNotEmpty &&
        ufNormUsuario.isNotEmpty) {
      return ufAd == ufNormUsuario;
    }
    return true;
  }

  /// Versão que recebe os campos brutos (`cidade` e `cidade_normalizada`) do
  /// documento e escolhe o que contém UF (formato `"Município — UF"`) para
  /// evitar matches de cidades homônimas (ex.: Toledo-PR ≠ Toledo-SC).
  ///
  /// Regras:
  /// - Se ambos estiverem vazios → depende de [globalSeVazio].
  /// - Se apenas um contém UF → usa esse.
  /// - Caso contrário, prefere `cidade_normalizada`.
  static bool anuncioCidadeCorrespondeUsuario({
    required String? cidadeNormalizada,
    required String? cidade,
    required String cidadeNormUsuario,
    required String ufNormUsuario,
    bool globalSeVazio = false,
  }) {
    final norm = (cidadeNormalizada ?? '').toString().trim();
    final raw = (cidade ?? '').toString().trim();
    final hasUfNorm = ufAnuncioOpcional(norm) != null;
    final hasUfRaw = ufAnuncioOpcional(raw) != null;
    final escolhido = hasUfRaw && !hasUfNorm
        ? raw
        : (norm.isNotEmpty ? norm : raw);
    return cidadeCampoCorrespondeUsuario(
      campoCidade: escolhido,
      cidadeNormUsuario: cidadeNormUsuario,
      ufNormUsuario: ufNormUsuario,
      globalSeVazio: globalSeVazio,
    );
  }

  LocationService() {
    _inicializar();
  }

  Future<void> _inicializar() async {
    final prefs = await SharedPreferences.getInstance();
    _cidadeDetectada = prefs.getString(_chaveCidade);
    _ufDetectado = prefs.getString(_chaveUf);
    _cidadeNormalizada = prefs.getString(_chaveCidadeNorm) ?? '';
    _ufNormalizado = prefs.getString(_chaveUfNorm) ?? '';

    // Web: geocoding nativo (plugin) não cobre browser; sessão pode reutilizar cidade salva.
    if (kIsWeb &&
        _cidadeNormalizada.isNotEmpty &&
        _ufNormalizado.isNotEmpty) {
      _deteccaoSessaoConfirmada = true;
    }

    await verificarTudo();
    _initialized = true;
    notifyListeners();

    if (!kIsWeb) {
      _serviceSubscription =
          Geolocator.getServiceStatusStream().listen((serviceStatus) {
        if (serviceStatus == ServiceStatus.disabled) {
          _atualizarStatus(LocationStatus.servicoDesativado);
          _positionSubscription?.cancel();
        } else {
          verificarTudo().then((_) {
            if (_status == LocationStatus.pronto) {
              detectarCidade();
            }
          });
        }
      });
    }
  }

  void _iniciarMonitoramento() {
    if (kIsWeb) {
      // getPositionStream / atualização contínua não é necessária na web e evita
      // incompatibilidades do plugin no browser.
      return;
    }
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        distanceFilter: 5000,
      ),
    ).listen(
      (Position position) {
        final distancia = (_ultimaLat != null && _ultimaLng != null)
            ? Geolocator.distanceBetween(
                _ultimaLat!,
                _ultimaLng!,
                position.latitude,
                position.longitude,
              )
            : double.infinity;

        if (distancia > 3000) {
          _ultimaLat = position.latitude;
          _ultimaLng = position.longitude;
          detectarCidade();
        }
      },
      onError: (e) {
        debugPrint('[LocationService] Erro no stream de posição: $e');
      },
    );
  }

  Future<void> verificarTudo() async {
    // No navegador não existe "serviço de localização" do SO como no Android.
    if (!kIsWeb) {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _atualizarStatus(LocationStatus.servicoDesativado);
        return;
      }
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      _atualizarStatus(LocationStatus.permissaoNegada);
      return;
    }
    if (permission == LocationPermission.deniedForever) {
      _atualizarStatus(LocationStatus.permissaoNegadaPermanente);
      return;
    }

    _atualizarStatus(LocationStatus.pronto);
  }

  Future<void> solicitarPermissao() async {
    var permission = await Geolocator.requestPermission();

    if (permission == LocationPermission.denied) {
      _atualizarStatus(LocationStatus.permissaoNegada);
      return;
    }
    if (permission == LocationPermission.deniedForever) {
      _atualizarStatus(LocationStatus.permissaoNegadaPermanente);
      return;
    }

    await verificarTudo();
    if (_status == LocationStatus.pronto) {
      await detectarCidade();
    }
  }

  static bool _textoGenericoOuVazio(String? s) {
    if (s == null) return true;
    final t = normalizar(s);
    if (t.isEmpty) return true;
    const invalidos = {'unknown', 'n/a', 'null', 'brasil', 'brazil', '-'};
    return invalidos.contains(t);
  }

  static bool _pareceRuaOuNumero(String s) {
    final t = s.trim();
    if (RegExp(r'^\d+[,\s]').hasMatch(t)) return true;
    final tl = t.toLowerCase();
    if (tl.contains('av.') ||
        tl.contains('avenida') ||
        tl.contains('rua ') ||
        tl.contains('rodovia')) {
      return true;
    }
    return false;
  }

  /// Prioridade: município administrativo (locality) → sub-região (subAdministrativeArea) → subLocality → name.
  static String? melhorNomeCidadePlacemark(Placemark p) {
    final estadoNorm =
        p.administrativeArea != null ? normalizar(p.administrativeArea!) : '';

    String? testar(String? raw) {
      if (raw == null) return null;
      final c = raw.trim();
      if (c.isEmpty || _textoGenericoOuVazio(c)) return null;
      if (_pareceRuaOuNumero(c)) return null;
      final cNorm = normalizar(c);
      if (_nomesEstadosCompletos.contains(cNorm)) return null;
      if (estadoNorm.isNotEmpty && cNorm == estadoNorm) return null;
      return c;
    }

    return testar(p.locality) ??
        testar(p.subAdministrativeArea) ??
        testar(p.subLocality) ??
        testar(p.name);
  }

  static String? ufDoPlacemark(Placemark p) {
    String? u = extrairUf(p.administrativeArea);
    u ??= extrairUf(p.subAdministrativeArea);
    return u;
  }

  /// Resolve cidade + UF a partir da lista retornada pelo geocoding (vários resultados = mais robustez).
  static ({String cidade, String uf})? resolverCidadeUfDePlacemarks(
    List<Placemark> lista,
  ) {
    for (final lugar in lista) {
      final uf = ufDoPlacemark(lugar);
      if (uf == null) continue;
      final cidade = melhorNomeCidadePlacemark(lugar);
      if (cidade != null && cidade.isNotEmpty) {
        return (cidade: cidade, uf: uf.toUpperCase());
      }
    }
    return null;
  }

  /// Rua, número e bairro a partir de um [Placemark] (reverso). Número vira `S/N` se o provedor não informar.
  static Map<String, String> linhasEnderecoDoPlacemark(Placemark p) {
    String rua = (p.thoroughfare ?? p.street ?? '').trim();
    final name = p.name?.trim() ?? '';
    if (rua.isEmpty && name.isNotEmpty) {
      final idx = name.indexOf(',');
      if (idx > 0) {
        rua = name.substring(0, idx).trim();
      } else if (!_textoGenericoOuVazio(name) && !_pareceRuaOuNumero(name)) {
        rua = name;
      }
    }
    String numero = (p.subThoroughfare ?? '').trim();
    if (numero.isEmpty && name.contains(',')) {
      final partes = name.split(',');
      final seg = partes.length >= 2 ? partes[1].trim() : '';
      final m = RegExp(r'^(\d+[a-zA-Z\-]?)').firstMatch(seg);
      if (m != null) numero = m.group(1)!;
    }
    if (numero.isEmpty) numero = 'S/N';
    String bairro = (p.subLocality ?? '').trim();
    return {'rua': rua, 'numero': numero, 'bairro': bairro};
  }

  ({String cidade, String uf})? _resolverRegiaoAdministrativa(List<Placemark> lista) {
    return resolverCidadeUfDePlacemarks(lista);
  }

  /// Flutter Web: o pacote [geocoding] não implementa reverse geocode no browser.
  /// Usa Nominatim (OSM), conforme uso recomendado (User-Agent identificável).
  Future<({String cidade, String uf})?> _reverseGeocodeNominatim(
    double lat,
    double lng,
  ) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng'
        '&format=json&addressdetails=1&accept-language=pt-BR',
      );
      final res = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'DiPertinCliente/1.0 (https://depertin.app)',
              'Accept-Language': 'pt-BR,pt;q=0.9',
            },
          )
          .timeout(const Duration(seconds: 14));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final addr = data['address'] as Map<String, dynamic>?;
      if (addr == null) return null;
      final cc = addr['country_code']?.toString().toLowerCase();
      if (cc != 'br') return null;

      String? cidade = addr['city']?.toString() ??
          addr['town']?.toString() ??
          addr['municipality']?.toString() ??
          addr['village']?.toString();
      if (cidade != null && _textoGenericoOuVazio(cidade)) cidade = null;
      if (cidade == null || cidade.trim().isEmpty) return null;

      String? ufStr = extrairUf(addr['state']?.toString());
      if (ufStr == null) {
        final iso = addr['ISO3166-2-lvl4']?.toString() ?? '';
        final m = RegExp(r'^BR-([A-Za-z]{2})$').firstMatch(iso);
        if (m != null) {
          ufStr = m.group(1)!.toLowerCase();
        }
      }
      if (ufStr == null || ufStr.length != 2) return null;

      return (cidade: cidade.trim(), uf: ufStr.toUpperCase());
    } catch (e) {
      debugPrint('[LocationService] Nominatim (web): $e');
      return null;
    }
  }

  Future<String?> detectarCidade() async {
    if (_status != LocationStatus.pronto) return _cidadeDetectada;
    if (_detectandoCidade) return _cidadeDetectada;

    _detectandoCidade = true;
    notifyListeners();

    try {
      // Na web getLastKnownPosition não existe (só getCurrentPosition).
      Position? position;
      if (!kIsWeb) {
        position = await Geolocator.getLastKnownPosition();
      }

      final posicaoAtual = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 18));

      if (position == null ||
          Geolocator.distanceBetween(
                position.latitude,
                position.longitude,
                posicaoAtual.latitude,
                posicaoAtual.longitude,
              ) >
              500) {
        position = posicaoAtual;
      }

      _ultimaLat = position.latitude;
      _ultimaLng = position.longitude;

      ({String cidade, String uf})? resolvido;

      if (kIsWeb) {
        resolvido = await _reverseGeocodeNominatim(
          position.latitude,
          position.longitude,
        );
      } else {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isEmpty) {
          placemarks = await placemarkFromCoordinates(
            posicaoAtual.latitude,
            posicaoAtual.longitude,
          );
        }

        if (placemarks.isNotEmpty) {
          resolvido = _resolverRegiaoAdministrativa(placemarks);
        }
      }

      if (resolvido != null) {
        final cidadeAnterior = _cidadeNormalizada;
        final ufAnterior = _ufNormalizado;

        await _salvarLocalizacao(resolvido.cidade, resolvido.uf);
        _deteccaoSessaoConfirmada = true;

        if (cidadeAnterior != _cidadeNormalizada ||
            ufAnterior != _ufNormalizado) {
          debugPrint(
            '[LocationService] Região atualizada: $_cidadeNormalizada / $_ufNormalizado',
          );
        }

        _iniciarMonitoramento();
      } else if (!kIsWeb) {
        debugPrint(
          '[LocationService] Geocoding não retornou cidade/UF utilizáveis.',
        );
      }
    } catch (e) {
      debugPrint('[LocationService] Erro ao detectar cidade: $e');
    } finally {
      _detectandoCidade = false;
      notifyListeners();
    }

    return _cidadeDetectada;
  }

  Future<void> _salvarLocalizacao(String cidade, String uf) async {
    final cidadeLimpa = cidade.trim();
    final ufLimpo = uf.trim();
    if (cidadeLimpa.isEmpty || ufLimpo.isEmpty) return;

    _cidadeDetectada = cidadeLimpa;
    _ufDetectado = ufLimpo;
    _cidadeNormalizada = normalizar(cidadeLimpa);
    _ufNormalizado = normalizar(ufLimpo);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chaveCidade, cidadeLimpa);
    await prefs.setString(_chaveUf, ufLimpo);
    await prefs.setString(_chaveCidadeNorm, _cidadeNormalizada);
    await prefs.setString(_chaveUfNorm, _ufNormalizado);
    notifyListeners();
  }

  Future<void> abrirConfiguracoes() async {
    await Geolocator.openAppSettings();
  }

  Future<void> abrirConfiguracoesLocalizacao() async {
    await Geolocator.openLocationSettings();
  }

  void _atualizarStatus(LocationStatus novoStatus) {
    if (_status != novoStatus) {
      _status = novoStatus;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _serviceSubscription?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }
}

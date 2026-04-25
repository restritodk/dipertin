// Arquivo: lib/screens/lojista/lojista_config_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../../constants/tipos_entrega.dart';
import '../../services/location_service.dart';
import '../../services/permissoes_app_service.dart';
import '../../utils/loja_pausa.dart';
import '../../widgets/loja_pausa_motivo_dialog.dart';
import 'configuracoes/tipos_entrega_loja_screen.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class LojistaConfigScreen extends StatefulWidget {
  const LojistaConfigScreen({super.key, required this.dadosAtuaisDaLoja});

  final Map<String, dynamic> dadosAtuaisDaLoja;

  @override
  State<LojistaConfigScreen> createState() => _LojistaConfigScreenState();
}

class _LojistaConfigScreenState extends State<LojistaConfigScreen> {
  late final TextEditingController _nomeLojaController;
  late final TextEditingController _enderecoLojaController;
  late final TextEditingController _telefoneController;

  bool _salvando = false;
  bool _buscandoLocalizacao = false;
  bool _pausadoManualmente = false;
  String? _pausaMotivo;
  Timestamp? _pausaVoltaAt;
  String _cidadeCapturada = '';
  String _ufCapturado = '';

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

  InputDecoration _decoration(String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, color: diPertinLaranja) : null,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: diPertinLaranja, width: 2),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final d = widget.dadosAtuaisDaLoja;
    _nomeLojaController = TextEditingController(
      text: d['loja_nome'] ?? d['nome'] ?? '',
    );
    _enderecoLojaController = TextEditingController(text: d['endereco'] ?? '');
    _telefoneController = TextEditingController(text: d['telefone'] ?? '');

    _pausadoManualmente = LojaPausa.lojaEfetivamentePausada(d);
    _pausaMotivo = _pausadoManualmente
        ? d['pausa_motivo']?.toString()
        : null;
    _pausaVoltaAt = _pausadoManualmente && d['pausa_volta_at'] is Timestamp
        ? d['pausa_volta_at'] as Timestamp
        : null;

    if (d['pausado_manualmente'] == true) {
      final patch = LojaPausa.patchSePausaAlmocoExpirada(d);
      if (patch.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final User? u = FirebaseAuth.instance.currentUser;
          if (u == null || !mounted) return;
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(u.uid)
                .update(patch);
          } catch (_) {}
          if (mounted) {
            setState(() {
              _pausadoManualmente = false;
              _pausaMotivo = null;
              _pausaVoltaAt = null;
            });
          }
        });
      }
    }

    final cidadeDoc = d['cidade']?.toString() ?? '';
    final ufDoc = d['uf']?.toString() ?? '';
    if (cidadeDoc.isNotEmpty) {
      _cidadeCapturada = cidadeDoc;
    }
    if (ufDoc.isNotEmpty) {
      _ufCapturado = ufDoc;
    }

    if (d['horarios'] != null) {
      final Map<String, dynamic> hBanco = d['horarios'] as Map<String, dynamic>;
      hBanco.forEach((key, value) {
        if (_horarios.containsKey(key)) {
          _horarios[key] = Map<String, dynamic>.from(value as Map);
        }
      });
    }
  }

  @override
  void dispose() {
    _nomeLojaController.dispose();
    _enderecoLojaController.dispose();
    _telefoneController.dispose();
    super.dispose();
  }

  int _minutosDoDia(String hhmm) {
    final partes = hhmm.split(':');
    if (partes.length < 2) return 0;
    final h = int.tryParse(partes[0]) ?? 0;
    final m = int.tryParse(partes[1]) ?? 0;
    return h * 60 + m;
  }

  /// Mesmo dia: abertura deve ser antes do fechamento (não cobre turno após meia-noite).
  bool _horariosConsistentes() {
    for (final entry in _horarios.entries) {
      final c = entry.value;
      if (c['ativo'] != true) continue;
      final abre = c['abre']?.toString() ?? '00:00';
      final fecha = c['fecha']?.toString() ?? '00:00';
      if (_minutosDoDia(abre) >= _minutosDoDia(fecha)) {
        return false;
      }
    }
    return true;
  }

  Future<void> _obterLocalizacaoDaLoja() async {
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

      if (placemarks.isEmpty) {
        throw Exception('Endereço não encontrado');
      }

      final Placemark place = placemarks[0];
      final String cidadeDetectada = place.locality?.isNotEmpty == true
          ? place.locality!
          : (place.subAdministrativeArea?.isNotEmpty == true
                ? place.subAdministrativeArea!
                : (place.administrativeArea ?? ''));

      final String? ufDetectado = LocationService.extrairUf(
        place.administrativeArea,
      );

      setState(() {
        _enderecoLojaController.text =
            '${place.thoroughfare ?? place.street ?? ''}, ${place.subThoroughfare ?? 'S/N'}, ${place.subLocality ?? ''} - $cidadeDetectada';
        _cidadeCapturada = cidadeDetectada;
        _ufCapturado = ufDetectado?.toUpperCase() ?? '';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Endereço preenchido pelo GPS. Confira antes de salvar.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('GPS/config endereço: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível usar o GPS. Digite o endereço manualmente.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _buscandoLocalizacao = false);
    }
  }

  String _subtituloSwitchPausa() {
    if (!_pausadoManualmente) {
      return 'Chuva, falta de luz, falta de estoque — a vitrine para de '
          'aceitar pedidos até você desligar.';
    }
    final buf = StringBuffer(PausaMotivoLoja.labelPt(_pausaMotivo));
    if (_pausaMotivo == PausaMotivoLoja.almoco && _pausaVoltaAt != null) {
      final dt = _pausaVoltaAt!.toDate();
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      buf.write(' — volta às $hh:$mm');
    }
    return buf.toString();
  }

  Future<void> _aoMudarPausa(bool valor) async {
    if (!valor) {
      setState(() {
        _pausadoManualmente = false;
        _pausaMotivo = null;
        _pausaVoltaAt = null;
      });
      return;
    }
    final escolha = await showLojaPausaMotivoDialog(
      context,
      accent: diPertinRoxo,
    );
    if (escolha == null || !mounted) return;
    setState(() {
      _pausadoManualmente = true;
      _pausaMotivo = escolha.motivo;
      _pausaVoltaAt = escolha.pausaVoltaAt;
    });
  }

  Future<void> _salvarConfiguracoes() async {
    if (_enderecoLojaController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o endereço de retirada da loja.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_horariosConsistentes()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Em algum dia ativo, o horário de abertura precisa ser antes do fechamento.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _salvando = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final Map<String, dynamic> dadosAtualizar = {
        'loja_nome': _nomeLojaController.text.trim(),
        'endereco': _enderecoLojaController.text.trim(),
        'telefone': _telefoneController.text.trim(),
        'horarios': _horarios,
      };

      if (!_pausadoManualmente) {
        dadosAtualizar['pausado_manualmente'] = false;
        dadosAtualizar['pausa_motivo'] = FieldValue.delete();
        dadosAtualizar['pausa_volta_at'] = FieldValue.delete();
      } else {
        dadosAtualizar['pausado_manualmente'] = true;
        dadosAtualizar['pausa_motivo'] = _pausaMotivo;
        if (_pausaMotivo == PausaMotivoLoja.almoco && _pausaVoltaAt != null) {
          dadosAtualizar['pausa_volta_at'] = _pausaVoltaAt;
        } else {
          dadosAtualizar['pausa_volta_at'] = FieldValue.delete();
        }
      }

      if (_cidadeCapturada.isNotEmpty) {
        dadosAtualizar['cidade'] = LocationService.normalizar(_cidadeCapturada);
        dadosAtualizar['uf'] = _ufCapturado;
        dadosAtualizar['cidade_normalizada'] = LocationService.normalizar(
          _cidadeCapturada,
        );
        dadosAtualizar['uf_normalizado'] =
            LocationService.extrairUf(_ufCapturado) ??
            LocationService.normalizar(_ufCapturado);
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update(dadosAtualizar);

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Configurações salvas com sucesso.'),
          backgroundColor: Colors.green,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Erro ao salvar config lojista: $e');
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _selecionarHora(String chaveDia, bool isAbre) async {
    final Map<String, dynamic> config = _horarios[chaveDia]!;
    final String horaAtualStr = isAbre ? config['abre'] : config['fecha'];

    final int h = int.parse(horaAtualStr.split(':')[0]);
    final int m = int.parse(horaAtualStr.split(':')[1]);

    final TimeOfDay? picked = await showTimePicker(
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
        final String hh = picked.hour.toString().padLeft(2, '0');
        final String mm = picked.minute.toString().padLeft(2, '0');
        _horarios[chaveDia]![isAbre ? 'abre' : 'fecha'] = '$hh:$mm';
      });
    }
  }

  Widget _buildLinhaHorario(String chaveDia) {
    final Map<String, dynamic> config = _horarios[chaveDia]!;
    final bool ativo = config['ativo'] == true;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Checkbox(
            value: ativo,
            fillColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return diPertinLaranja;
              }
              return null;
            }),
            onChanged: (bool? val) =>
                setState(() => _horarios[chaveDia]!['ativo'] = val ?? false),
          ),
          SizedBox(
            width: 76,
            child: Text(
              _nomesDias[chaveDia]!,
              style: TextStyle(
                fontWeight: ativo ? FontWeight.w700 : FontWeight.w500,
                color: ativo ? const Color(0xFF1A1A2E) : Colors.grey,
              ),
            ),
          ),
          if (ativo) ...[
            Expanded(
              child: InkWell(
                onTap: () => _selecionarHora(chaveDia, true),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    config['abre'].toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('às'),
            ),
            Expanded(
              child: InkWell(
                onTap: () => _selecionarHora(chaveDia, false),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    config['fecha'].toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ] else
            const Expanded(
              child: Text(
                'Fechado',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _secaoTitulo(String titulo, IconData icone) {
    return Row(
      children: [
        Icon(icone, size: 22, color: diPertinRoxo),
        const SizedBox(width: 8),
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: diPertinRoxo,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
      child: child,
    );
  }

  Widget _cardTiposEntregaAtalho() {
    final List<String> tiposAtuais = TiposEntrega.lerDeDoc(
      widget.dadosAtuaisDaLoja,
    );
    final bool configurado = tiposAtuais.isNotEmpty;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: configurado
                      ? Colors.green.withValues(alpha: 0.12)
                      : Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  configurado
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_rounded,
                  color: configurado ? Colors.green.shade700 : Colors.red.shade700,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Tipos de entrega aceitos',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            configurado
                ? 'Você aceita: ${tiposAtuais.map(TiposEntrega.rotulo).join(', ')}. '
                    'O frete é calculado pelo tipo mais caro para proteger seu custo de logística.'
                : 'Você ainda não configurou os tipos de veículos aceitos para '
                    'suas entregas. Isso é essencial — o sistema usa essa '
                    'configuração para calcular o frete e chamar o entregador certo.',
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.grey.shade800,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TiposEntregaLojaScreen(),
                  ),
                );
                if (mounted) setState(() {});
              },
              style: FilledButton.styleFrom(
                backgroundColor: diPertinRoxo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
                elevation: 0,
              ),
              icon: Icon(
                configurado ? Icons.tune_rounded : Icons.rocket_launch_rounded,
                size: 18,
              ),
              label: Text(
                configurado ? 'Editar tipos aceitos' : 'Configurar agora',
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool temCidadeUf =
        _cidadeCapturada.isNotEmpty || _ufCapturado.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      appBar: AppBar(
        title: const Text(
          'Configuração operacional',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: diPertinRoxo,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _secaoTitulo('Dados comerciais', Icons.storefront_outlined),
            const SizedBox(height: 12),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nomeLojaController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _decoration(
                      'Nome da loja',
                      icon: Icons.badge_outlined,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _telefoneController,
                    keyboardType: TextInputType.phone,
                    decoration: _decoration(
                      'Telefone / WhatsApp',
                      hint: 'DDD + número',
                      icon: Icons.phone_outlined,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Endereço de retirada',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _buscandoLocalizacao
                            ? null
                            : _obterLocalizacaoDaLoja,
                        icon: _buscandoLocalizacao
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: diPertinLaranja,
                                ),
                              )
                            : const Icon(Icons.my_location, size: 18),
                        label: const Text('Usar GPS'),
                        style: TextButton.styleFrom(
                          foregroundColor: diPertinLaranja,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _enderecoLojaController,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration:
                        _decoration(
                          'Endereço completo',
                          hint: 'Rua, número, bairro, cidade',
                          icon: Icons.location_on_outlined,
                        ).copyWith(
                          prefixIcon: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                          ),
                        ),
                  ),
                  if (temCidadeUf) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: diPertinRoxo.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: diPertinRoxo,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Cidade/UF usados na vitrine: '
                              '${_cidadeCapturada.isEmpty ? '—' : _cidadeCapturada}'
                              '${_ufCapturado.isEmpty ? '' : ' / $_ufCapturado'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade800,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Este endereço é usado pelo entregador para buscar na loja.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            _secaoTitulo('Operação na vitrine', Icons.toggle_on_outlined),
            const SizedBox(height: 8),
            Text(
              'A pausa fecha as vendas na hora. Os horários abaixo informam ao cliente quando você costuma atender.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            _card(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Pausar loja agora',
                  style: TextStyle(
                    color: _pausadoManualmente
                        ? Colors.red.shade800
                        : const Color(0xFF1A1A2E),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  _subtituloSwitchPausa(),
                  style: const TextStyle(fontSize: 12),
                ),
                value: _pausadoManualmente,
                activeThumbColor: Colors.red,
                activeTrackColor: Colors.red.withValues(alpha: 0.45),
                onChanged: (valor) async => _aoMudarPausa(valor),
              ),
            ),

            const SizedBox(height: 20),
            _secaoTitulo(
              'Logística da entrega',
              Icons.two_wheeler_outlined,
            ),
            const SizedBox(height: 12),
            _cardTiposEntregaAtalho(),

            const SizedBox(height: 20),
            _secaoTitulo('Horários por dia', Icons.schedule),
            const SizedBox(height: 12),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...[
                    'domingo',
                    'segunda',
                    'terca',
                    'quarta',
                    'quinta',
                    'sexta',
                    'sabado',
                  ].map((dia) => _buildLinhaHorario(dia)),
                ],
              ),
            ),

            const SizedBox(height: 24),
            FilledButton(
              onPressed: _salvando ? null : _salvarConfiguracoes,
              style: FilledButton.styleFrom(
                backgroundColor: diPertinLaranja,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _salvando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Salvar configurações',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

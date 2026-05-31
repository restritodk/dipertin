import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);

/// Resultado da seleção de endereço para entrega no checkout.
class EnderecoEntregaResultado {
  const EnderecoEntregaResultado({
    required this.textoEntrega,
    required this.mapa,
  });

  /// Texto usado no frete e no pedido/encomenda.
  final String textoEntrega;

  /// Campos estruturados (rua, numero, bairro, cidade, estado, cep, complemento).
  final Map<String, dynamic> mapa;
}

/// Formata mapa de endereço para exibição e geocoding.
String formatarEnderecoEntregaMapa(Map<String, dynamic> m) {
  final rua = (m['rua'] ?? '').toString().trim();
  final num = (m['numero'] ?? '').toString().trim();
  final bairro = (m['bairro'] ?? '').toString().trim();
  final cidade = (m['cidade'] ?? '').toString().trim();
  final estado =
      (m['estado'] ?? m['uf'] ?? '').toString().trim().toUpperCase();
  final comp = (m['complemento'] ?? '').toString().trim();
  final buf = StringBuffer();
  if (rua.isNotEmpty) {
    buf.write(rua);
    if (num.isNotEmpty) buf.write(', $num');
  }
  if (bairro.isNotEmpty) {
    if (buf.isNotEmpty) buf.write(', ');
    buf.write(bairro);
  }
  if (cidade.isNotEmpty) {
    if (buf.isNotEmpty) buf.write(', ');
    buf.write(cidade);
    if (estado.isNotEmpty) buf.write(' - $estado');
  }
  if (comp.isNotEmpty) {
    if (buf.isNotEmpty) buf.write(' — ');
    buf.write(comp);
  }
  final s = buf.toString().trim();
  return s.isEmpty ? 'Endereço não informado' : s;
}

/// Abre o sheet e retorna o endereço escolhido ou `null` se cancelado.
Future<EnderecoEntregaResultado?> mostrarSelecionarEnderecoEntregaSheet(
  BuildContext context,
) {
  return showModalBottomSheet<EnderecoEntregaResultado>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _SelecionarEnderecoEntregaSheet(),
  );
}

class _EnderecoOpcao {
  _EnderecoOpcao({
    this.docId,
    required this.mapa,
    required this.principal,
    required this.rotulo,
  });

  final String? docId;
  final Map<String, dynamic> mapa;
  final bool principal;
  final String rotulo;
}

class _SelecionarEnderecoEntregaSheet extends StatefulWidget {
  const _SelecionarEnderecoEntregaSheet();

  @override
  State<_SelecionarEnderecoEntregaSheet> createState() =>
      _SelecionarEnderecoEntregaSheetState();
}

class _SelecionarEnderecoEntregaSheetState
    extends State<_SelecionarEnderecoEntregaSheet> {
  bool _carregando = true;
  String? _erro;
  List<_EnderecoOpcao> _opcoes = [];
  bool _modoCep = false;
  bool _buscandoCep = false;
  bool _salvando = false;
  bool _salvarNaConta = true;
  bool _definirComoPadrao = true;

  final _cepC = TextEditingController();
  final _ruaC = TextEditingController();
  final _numeroC = TextEditingController();
  final _bairroC = TextEditingController();
  final _cidadeC = TextEditingController();
  final _estadoC = TextEditingController();
  final _complementoC = TextEditingController();
  final _numeroFocus = FocusNode();
  String _ultimoCepBuscado = '';

  @override
  void initState() {
    super.initState();
    _carregarEnderecos();
  }

  @override
  void dispose() {
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

  static String _chaveEndereco(Map<String, dynamic> m) {
    String n(String? v) => (v ?? '').toString().trim().toLowerCase();
    return '${n(m['rua'])}|${n(m['numero'])}|${n(m['bairro'])}|${n(m['cidade'])}|'
        '${n(m['estado'] ?? m['uf'])}|${n(m['complemento'])}';
  }

  static bool _mesmoEndereco(Map<String, dynamic> a, Map<String, dynamic> b) {
    return _chaveEndereco(a) == _chaveEndereco(b);
  }

  Future<void> _carregarEnderecos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _carregando = false;
        _erro = 'Faça login para escolher o endereço.';
      });
      return;
    }
    try {
      final userSnap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final dados = userSnap.data() ?? {};
      Map<String, dynamic>? padrao;
      if (dados['endereco_entrega_padrao'] is Map) {
        padrao = Map<String, dynamic>.from(
          dados['endereco_entrega_padrao'] as Map,
        );
      }

      final endSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('enderecos')
          .orderBy('criado_em', descending: true)
          .get();

      final lista = <_EnderecoOpcao>[];
      var temDocPadrao = false;

      if (padrao != null && padrao.isNotEmpty) {
        for (final doc in endSnap.docs) {
          final m = Map<String, dynamic>.from(doc.data());
          if (_mesmoEndereco(m, padrao)) {
            temDocPadrao = true;
            break;
          }
        }
        if (!temDocPadrao) {
          lista.add(
            _EnderecoOpcao(
              mapa: padrao,
              principal: true,
              rotulo: 'Padrão de entrega',
            ),
          );
        }
      }

      for (final doc in endSnap.docs) {
        final m = Map<String, dynamic>.from(doc.data());
        final ehPrincipal =
            padrao != null && _mesmoEndereco(m, padrao);
        lista.add(
          _EnderecoOpcao(
            docId: doc.id,
            mapa: m,
            principal: ehPrincipal,
            rotulo: ehPrincipal ? 'Padrão de entrega' : 'Salvo',
          ),
        );
      }

      lista.sort((a, b) {
        if (a.principal == b.principal) return 0;
        return a.principal ? -1 : 1;
      });

      if (!mounted) return;
      setState(() {
        _opcoes = lista;
        _carregando = false;
        _erro = lista.isEmpty ? 'Nenhum endereço salvo ainda.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Erro ao carregar endereços: $e';
      });
    }
  }

  void _selecionar(_EnderecoOpcao op) {
    final mapa = Map<String, dynamic>.from(op.mapa);
    Navigator.pop(
      context,
      EnderecoEntregaResultado(
        textoEntrega: formatarEnderecoEntregaMapa(mapa),
        mapa: mapa,
      ),
    );
  }

  Future<void> _buscarPorCep({bool silencioso = false}) async {
    final cep = _apenasDigitos(_cepC.text);
    if (cep.length != 8) {
      if (!silencioso && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe um CEP com 8 dígitos.')),
        );
      }
      return;
    }
    if (cep == _ultimoCepBuscado) return;

    setState(() => _buscandoCep = true);
    try {
      final res = await http
          .get(Uri.parse('https://viacep.com.br/ws/$cep/json/'))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['erro'] == true) {
        if (!silencioso && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('CEP não encontrado.')),
          );
        }
        return;
      }
      _ultimoCepBuscado = cep;
      _ruaC.text = (data['logradouro'] ?? '').toString().trim();
      _bairroC.text = (data['bairro'] ?? '').toString().trim();
      _cidadeC.text = (data['localidade'] ?? '').toString().trim();
      _estadoC.text =
          (data['uf'] ?? '').toString().trim().toUpperCase();
      _numeroC.clear();
      _focarNumero();
    } catch (e) {
      if (!silencioso && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível buscar o CEP: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _buscandoCep = false);
    }
  }

  void _focarNumero() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _numeroFocus.requestFocus();
    });
  }

  Map<String, dynamic> _mapaDoFormulario() {
    return {
      'cep': _apenasDigitos(_cepC.text),
      'rua': _ruaC.text.trim(),
      'numero': _numeroC.text.trim(),
      'bairro': _bairroC.text.trim(),
      'cidade': _cidadeC.text.trim().toLowerCase(),
      'estado': _estadoC.text.trim().toUpperCase(),
      'complemento': _complementoC.text.trim(),
      'data_atualizacao': FieldValue.serverTimestamp(),
    };
  }

  Future<void> _confirmarEnderecoCep() async {
    final mapa = _mapaDoFormulario();
    if ((mapa['rua'] as String).isEmpty ||
        (mapa['numero'] as String).isEmpty ||
        (mapa['bairro'] as String).isEmpty ||
        (mapa['cidade'] as String).isEmpty ||
        (mapa['estado'] as String).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha rua, número, bairro, cidade e UF.'),
        ),
      );
      return;
    }

    if (!_salvarNaConta) {
      Navigator.pop(
        context,
        EnderecoEntregaResultado(
          textoEntrega: formatarEnderecoEntregaMapa(mapa),
          mapa: mapa,
        ),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _salvando = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

      if (_definirComoPadrao) {
        batch.set(
          userRef,
          {
            'endereco_entrega_padrao': mapa,
            // Não altera cidade/UF do perfil — vitrine e busca usam só GPS
            // ([LocationService]), independente do endereço de entrega.
            'endereco': formatarEnderecoEntregaMapa(mapa),
          },
          SetOptions(merge: true),
        );
      }

      final endRef = userRef.collection('enderecos').doc();
      batch.set(endRef, {
        ...mapa,
        'criado_em': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (!mounted) return;
      Navigator.pop(
        context,
        EnderecoEntregaResultado(
          textoEntrega: formatarEnderecoEntregaMapa(mapa),
          mapa: mapa,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar endereço: $e')),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Endereço de entrega',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _roxo,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: _modoCep ? _buildFormCep() : _buildLista(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLista() {
    if (_carregando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator(color: _roxo)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: () => setState(() => _modoCep = true),
          icon: const Icon(Icons.search, color: _roxo),
          label: const Text(
            'Buscar por CEP ou novo endereço',
            style: TextStyle(fontWeight: FontWeight.w700, color: _roxo),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: BorderSide(color: _roxo.withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_erro != null)
          Text(
            _erro!,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ..._opcoes.map((op) {
          final texto = formatarEnderecoEntregaMapa(op.mapa);
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: op.principal ? _roxo.withValues(alpha: 0.35) : Colors.grey.shade200,
              ),
            ),
            child: ListTile(
              onTap: () => _selecionar(op),
              leading: Icon(
                op.principal ? Icons.star : Icons.location_on_outlined,
                color: op.principal ? _laranja : _roxo,
              ),
              title: Text(
                op.rotulo,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: op.principal ? _roxo : Colors.grey.shade700,
                ),
              ),
              subtitle: Text(texto),
              trailing: const Icon(Icons.chevron_right),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildFormCep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _modoCep = false),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Voltar aos endereços salvos'),
        ),
        TextField(
          controller: _cepC,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
            _CepInputFormatter(),
          ],
          onChanged: (v) {
            if (_apenasDigitos(v).length == 8) {
              _buscarPorCep(silencioso: true);
            }
          },
          decoration: InputDecoration(
            labelText: 'CEP',
            suffixIcon: _buscandoCep
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () => _buscarPorCep(),
                  ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _ruaC,
          decoration: const InputDecoration(
            labelText: 'Rua',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _numeroC,
                focusNode: _numeroFocus,
                decoration: const InputDecoration(
                  labelText: 'Número',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: TextField(
                controller: _complementoC,
                decoration: const InputDecoration(
                  labelText: 'Complemento',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _bairroC,
          decoration: const InputDecoration(
            labelText: 'Bairro',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _cidadeC,
                decoration: const InputDecoration(
                  labelText: 'Cidade',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _estadoC,
                maxLength: 2,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'UF',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _salvarNaConta,
          activeThumbColor: _roxo,
          onChanged: (v) => setState(() => _salvarNaConta = v),
          title: const Text(
            'Salvar na minha conta',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Desligue para usar só neste pedido',
            style: TextStyle(fontSize: 12),
          ),
        ),
        if (_salvarNaConta)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _definirComoPadrao,
            activeThumbColor: _laranja,
            onChanged: (v) => setState(() => _definirComoPadrao = v),
            title: const Text(
              'Definir como endereço padrão',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _salvando ? null : _confirmarEnderecoCep,
          style: FilledButton.styleFrom(
            backgroundColor: _laranja,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _salvando
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  'Usar este endereço',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
        ),
      ],
    );
  }
}

class _CepInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final d = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) {
      return const TextEditingValue(text: '');
    }
    if (d.length <= 5) {
      return TextEditingValue(
        text: d,
        selection: TextSelection.collapsed(offset: d.length),
      );
    }
    final t = '${d.substring(0, 5)}-${d.substring(5, d.length > 8 ? 8 : d.length)}';
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}

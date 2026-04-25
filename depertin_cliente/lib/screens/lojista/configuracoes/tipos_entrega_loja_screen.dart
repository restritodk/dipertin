// Arquivo: lib/screens/lojista/configuracoes/tipos_entrega_loja_screen.dart
//
// Tela onde o lojista escolhe quais tipos de veículo aceita para entregar os
// produtos da sua loja. Essa configuração controla:
//   1. Qual tabela de frete o carrinho vai usar (regra mestre: maior
//      hierarquia vence — ver TiposEntrega.maiorTipoDaLista).
//   2. Quais entregadores serão chamados (filtro server-side em
//      construirFilaEntregadores).
//
// Persiste em `users/{uid}.tipos_entrega_permitidos` (List<String>) + timestamp.
// O trigger `sincronizarLojaPublicOnWrite` espelha em
// `lojas_public/{uid}.tipos_entrega_permitidos`, que é o doc lido pelo
// carrinho sem expor dados sensíveis do lojista.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../constants/tipos_entrega.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);

class TiposEntregaLojaScreen extends StatefulWidget {
  const TiposEntregaLojaScreen({super.key});

  @override
  State<TiposEntregaLojaScreen> createState() => _TiposEntregaLojaScreenState();
}

class _TiposEntregaLojaScreenState extends State<TiposEntregaLojaScreen> {
  bool _carregando = true;
  bool _salvando = false;
  Set<String> _selecionados = <String>{};
  List<String> _selecionadosIniciais = <String>[];

  String? get _uidLoja => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final uid = _uidLoja;
    if (uid == null) {
      if (mounted) setState(() => _carregando = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final atuais = TiposEntrega.lerDeDoc(snap.data());
      if (mounted) {
        setState(() {
          _selecionados = atuais.toSet();
          _selecionadosIniciais = atuais;
          _carregando = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  bool get _alterado {
    if (_selecionados.length != _selecionadosIniciais.length) return true;
    for (final t in _selecionadosIniciais) {
      if (!_selecionados.contains(t)) return true;
    }
    return false;
  }

  bool get _marcouBike => _selecionados.contains(TiposEntrega.codBicicleta);
  bool get _marcouSoBike =>
      _selecionados.length == 1 && _selecionados.contains(TiposEntrega.codBicicleta);
  bool get _temSomenteLeve =>
      _selecionados.isNotEmpty &&
      !_selecionados.contains(TiposEntrega.codCarro) &&
      !_selecionados.contains(TiposEntrega.codCarroFrete);

  Future<void> _salvar() async {
    final uid = _uidLoja;
    if (uid == null) return;
    if (_selecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione ao menos um tipo de entrega.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _salvando = true);
    try {
      final lista = TiposEntrega.paraFirestore(_selecionados.toList());
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'tipos_entrega_permitidos': lista,
        'tipos_entrega_atualizado_em': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _selecionadosIniciais = lista;
        _salvando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuração salva. As próximas corridas já seguem a nova regra.'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  IconData _iconePorTipo(String codigo) {
    switch (codigo) {
      case TiposEntrega.codBicicleta:
        return Icons.pedal_bike_rounded;
      case TiposEntrega.codMoto:
        return Icons.two_wheeler_rounded;
      case TiposEntrega.codCarro:
        return Icons.directions_car_rounded;
      case TiposEntrega.codCarroFrete:
        return Icons.local_shipping_rounded;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      appBar: AppBar(
        title: const Text(
          'Tipos de entrega aceitos',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _roxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: _laranja))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _cardExplicacao(),
                  const SizedBox(height: 16),
                  ...TiposEntrega.ordemCanonica.map(_linhaTipo),
                  const SizedBox(height: 16),
                  if (_temSomenteLeve) _avisoSoLeve(),
                  if (_marcouBike) _avisoBike(),
                  if (_selecionados.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _resumoDaEscolha(),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: (_salvando || !_alterado) ? null : _salvar,
                    style: FilledButton.styleFrom(
                      backgroundColor: _laranja,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _salvando
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Salvar configuração',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              letterSpacing: 0.2,
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _cardExplicacao() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _roxo.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.lightbulb_outline, color: _laranja),
              SizedBox(width: 8),
              Text(
                'Como isso funciona',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Selecione os tipos de veículos compatíveis com os produtos da '
            'sua loja. Se seus produtos forem grandes, pesados ou volumosos, '
            'recomendamos selecionar apenas Carro ou Carro frete.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 10),
          Text(
            'Produtos como geladeira, fogão, móveis, caixas grandes ou itens '
            'pesados NÃO devem ser configurados para moto ou bicicleta.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Colors.grey.shade800,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _linhaTipo(String codigo) {
    final selecionado = _selecionados.contains(codigo);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selecionado
              ? _laranja
              : Colors.grey.shade300,
          width: selecionado ? 2 : 1,
        ),
      ),
      child: CheckboxListTile(
        value: selecionado,
        activeColor: _laranja,
        controlAffinity: ListTileControlAffinity.trailing,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 4,
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: selecionado
                  ? _laranja.withValues(alpha: 0.15)
                  : Colors.grey.shade100,
              child: Icon(
                _iconePorTipo(codigo),
                color: selecionado ? _laranja : Colors.grey.shade700,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TiposEntrega.rotulo(codigo),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    TiposEntrega.descricaoCurta(codigo),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        onChanged: (v) {
          setState(() {
            if (v == true) {
              _selecionados.add(codigo);
            } else {
              _selecionados.remove(codigo);
            }
          });
        },
      ),
    );
  }

  Widget _avisoBike() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _laranja.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _laranja.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: _laranja, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _marcouSoBike
                  ? 'Bicicleta é recomendada apenas para entregas pequenas e próximas '
                      '(até ~2 km da loja). Se sua loja atende distâncias maiores, considere '
                      'também habilitar Moto ou Carro.'
                  : 'Bicicleta será usada apenas para entregas pequenas e curtas. '
                      'Para distâncias maiores, o sistema chamará entregador de moto ou carro.',
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avisoSoLeve() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Se sua loja vende produtos grandes ou pesados (móveis, '
              'eletrodomésticos, caixas volumosas), é muito importante habilitar '
              'Carro ou Carro frete. Entregador de moto ou bicicleta pode recusar '
              'a corrida ao chegar e ver o produto — isso atrasa sua entrega.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Colors.red.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resumoDaEscolha() {
    final selec = _selecionados.toList()
      ..sort(
        (a, b) => (TiposEntrega.hierarquia[a] ?? 0)
            .compareTo(TiposEntrega.hierarquia[b] ?? 0),
      );
    final maior = TiposEntrega.maiorTipoDaLista(selec);
    final rotuloMaior = maior == null ? '—' : TiposEntrega.rotulo(maior);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _roxo.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _roxo.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.calculate_outlined, color: _roxo, size: 20),
              SizedBox(width: 8),
              Text(
                'O que muda no frete',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _roxo,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Frete será calculado pela tabela de "$rotuloMaior" — o tipo de '
            'maior custo entre os que você aceita. Isso evita prejuízo caso '
            'a corrida seja aceita por um entregador desse tipo.',
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: selec
                .map((t) => _chipTipo(t, destaque: t == maior))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _chipTipo(String codigo, {bool destaque = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: destaque ? _laranja : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: destaque ? _laranja : Colors.grey.shade300,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _iconePorTipo(codigo),
            size: 14,
            color: destaque ? Colors.white : Colors.grey.shade800,
          ),
          const SizedBox(width: 5),
          Text(
            TiposEntrega.rotulo(codigo),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: destaque ? Colors.white : Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }
}

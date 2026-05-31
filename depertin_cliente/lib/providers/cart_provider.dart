// Arquivo: lib/providers/cart_provider.dart

import 'dart:convert'; // Para trabalhar com JSON
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // O nosso "bloco de notas"
import '../models/cart_item_model.dart';

class CartProvider with ChangeNotifier {
  List<CartItemModel> _items = [];

  // Quando o Provider nascer (o app abrir), ele tenta ler o bloco de notas
  CartProvider() {
    _loadCart();
  }

  List<CartItemModel> get items => [..._items];

  // ATUALIZADO: Agora ele soma a quantidade de itens reais (ex: 2 hambúrgueres = 2 na bolinha laranja)
  int get itemCount => _items.length;

  double get totalAmount {
    var total = 0.0;
    for (var item in _items) {
      total += item.preco * item.quantidade;
    }
    return total;
  }

  // ==========================================
  // CONVIVÊNCIA ENTRE ENCOMENDA E PRONTA-ENTREGA
  // A sacola pode conter os dois tipos ao mesmo tempo; cada tipo é
  // finalizado em sua própria seção/fluxo.
  // ==========================================
  List<CartItemModel> get itensEncomenda =>
      _items.where((i) => i.ehEncomenda).toList();

  List<CartItemModel> get itensProntaEntrega =>
      _items.where((i) => !i.ehEncomenda).toList();

  bool get temEncomenda => _items.any((i) => i.ehEncomenda);

  bool get temProntaEntrega => _items.any((i) => !i.ehEncomenda);

  /// Soma apenas os itens de pronta-entrega (base do checkout normal).
  double get totalProntaEntrega {
    var total = 0.0;
    for (final item in _items) {
      if (!item.ehEncomenda) total += item.preco * item.quantidade;
    }
    return total;
  }

  /// Remove da sacola somente os itens do tipo informado, preservando os do
  /// outro tipo. Usado ao finalizar uma das seções (normal ou encomenda).
  Future<void> removerItensPorTipo({required bool encomenda}) async {
    _items.removeWhere((i) => i.ehEncomenda == encomenda);
    notifyListeners();
    await _saveCart();
  }

  // ==========================================
  // LÓGICA DE SALVAR NO CELULAR (MAGIA AQUI)
  // ==========================================
  Future<void> _saveCart() async {
    final prefs = await SharedPreferences.getInstance();
    final String cartString = json.encode(
      _items.map((item) => item.toJson()).toList(),
    );
    await prefs.setString('carrinho_depertin', cartString);
  }

  Future<void> _loadCart() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cartString = prefs.getString('carrinho_depertin');

    if (cartString != null) {
      final List<dynamic> decodedData = json.decode(cartString);
      _items = decodedData.map((item) => CartItemModel.fromJson(item)).toList();
      notifyListeners();
    }
  }

  // ==========================================
  // FUNÇÕES DO CARRINHO
  // ==========================================
  void addItem(CartItemModel product) {
    addItemWithQuantity(product, 1);
  }

  /// Retorna mensagem de bloqueio ou `null` se incluiu/atualizou com sucesso.
  String? addItemWithQuantity(CartItemModel product, int quantidade) {
    if (quantidade <= 0) return null;
    // Encomenda e pronta-entrega podem coexistir na sacola (finalizadas em
    // seções separadas). Mantemos apenas a regra de que uma ENCOMENDA só pode
    // ter itens de uma loja por vez — comparando somente com os itens de
    // encomenda já presentes, não com o primeiro item da sacola.
    if (product.ehEncomenda && product.lojaId.trim().isNotEmpty) {
      final encomendaOutraLoja = _items.any(
        (i) =>
            i.ehEncomenda &&
            i.lojaId.trim().isNotEmpty &&
            i.lojaId.trim() != product.lojaId.trim(),
      );
      if (encomendaOutraLoja) {
        return 'Encomendas só podem ter itens de uma loja por vez. '
            'Finalize ou remova a encomenda atual para iniciar outra.';
      }
    }
    final index = _items.indexWhere(
      (i) => i.chaveCarrinho == product.chaveCarrinho,
    );

    if (index >= 0) {
      _items[index].quantidade += quantidade;
    } else {
      _items.add(
        CartItemModel(
          id: product.id,
          nome: product.nome,
          preco: product.preco,
          lojaId: product.lojaId,
          lojaNome: product.lojaNome,
          imagem: product.imagem,
          quantidade: quantidade,
          requerVeiculoGrande: product.requerVeiculoGrande,
          ehEncomenda: product.ehEncomenda,
          variacoesSelecionadas: product.variacoesSelecionadas,
        ),
      );
    }
    notifyListeners();
    _saveCart();
    return null;
  }

  // --- NOVAS FUNÇÕES PARA OS BOTÕES + E - ---
  void incrementarQuantidade(String chaveCarrinho) {
    final index = _items.indexWhere((i) => i.chaveCarrinho == chaveCarrinho);
    if (index >= 0) {
      _items[index].quantidade += 1;
      notifyListeners();
      _saveCart(); // Salva a nova quantidade no celular
    }
  }

  void decrementarQuantidade(String chaveCarrinho) {
    final index = _items.indexWhere((i) => i.chaveCarrinho == chaveCarrinho);
    if (index >= 0) {
      if (_items[index].quantidade > 1) {
        _items[index].quantidade -= 1;
      } else {
        _items.removeAt(index); // Se chegar a zero, remove do carrinho
      }
      notifyListeners();
      _saveCart(); // Salva a nova quantidade no celular
    }
  }
  // ------------------------------------------

  // Mantido para compatibilidade caso outro lugar do app use
  void removeSingleItem(String productId) {
    decrementarQuantidade(productId);
  }

  void removeItem(String chaveCarrinho) {
    _items.removeWhere((item) => item.chaveCarrinho == chaveCarrinho);
    notifyListeners();
    _saveCart();
  }

  Future<void> clearCart() async {
    _items.clear();
    notifyListeners();
    await _saveCart();
  }
}

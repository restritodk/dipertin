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

  /// Adiciona várias unidades de uma vez (detalhe do produto).
  void addItemWithQuantity(CartItemModel product, int quantidade) {
    if (quantidade <= 0) return;
    final index = _items.indexWhere((i) => i.id == product.id);

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
        ),
      );
    }
    notifyListeners();
    _saveCart();
  }

  // --- NOVAS FUNÇÕES PARA OS BOTÕES + E - ---
  void incrementarQuantidade(String id) {
    final index = _items.indexWhere((i) => i.id == id);
    if (index >= 0) {
      _items[index].quantidade += 1;
      notifyListeners();
      _saveCart(); // Salva a nova quantidade no celular
    }
  }

  void decrementarQuantidade(String id) {
    final index = _items.indexWhere((i) => i.id == id);
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

  void removeItem(String productId) {
    _items.removeWhere((item) => item.id == productId);
    notifyListeners();
    _saveCart();
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
    _saveCart();
  }
}

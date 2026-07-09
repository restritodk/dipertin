import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/models/venda_historico_model.dart';
import 'package:depertin_web/utils/firestore_web_safe.dart';

/// Serviço de histórico de vendas da Gestão Comercial.
///
/// Busca dados da coleção `gestao_comercial_vendas` filtrando por `loja_id`.
/// Toda a lógica é local (não altera Firestore, não altera services existentes).
abstract final class VendasHistoricoService {
  static CollectionReference<Map<String, dynamic>> _vendasCol() =>
      FirebaseFirestore.instance.collection('gestao_comercial_vendas');

  /// Carga única filtrada por [lojaId].
  /// Aplica filtro de período no Firestore (data_venda) e
  /// demais filtros localmente.
  static Future<List<VendaHistorico>> carregarVendas({
    required String lojaId,
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async {
    if (lojaId.isEmpty) return [];
    try {
      var query = _vendasCol()
          .where('loja_id', isEqualTo: lojaId)
          .orderBy('data_venda', descending: true);

      if (dataInicio != null) {
        query = query.where('data_venda',
            isGreaterThanOrEqualTo: Timestamp.fromDate(dataInicio));
      }
      if (dataFim != null) {
        final fim = DateTime(dataFim.year, dataFim.month, dataFim.day, 23, 59, 59);
        query = query.where('data_venda',
            isLessThanOrEqualTo: Timestamp.fromDate(fim));
      }

      final snap = await query.get();
      return snap.docs
          .map((d) => VendaHistorico.fromDoc(d.id, safeWebDocData(d)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Aplica filtros client-side (busca, status, forma de pagamento).
  static List<VendaHistorico> aplicarFiltros(
    List<VendaHistorico> vendas, {
    String busca = '',
    String status = 'Todos',
    String formaPagamento = 'Todos',
  }) {
    var lista = vendas;

    if (busca.trim().isNotEmpty) {
      final q = busca.trim().toLowerCase();
      lista = lista.where((v) {
        return (v.clienteNome?.toLowerCase().contains(q) ?? false) ||
            (v.clienteDocumento?.toLowerCase().contains(q) ?? false) ||
            v.codigoExibicao.toLowerCase().contains(q) ||
            v.itens.any((i) => i.produtoNome.toLowerCase().contains(q));
      }).toList();
    }

    if (status != 'Todos') {
      lista = lista.where((v) {
        switch (status) {
          case 'Pago':
            return v.status == 'pago';
          case 'Pendente':
            return v.status == 'pendente' || v.status == 'parcial';
          case 'Parcial':
            return v.status == 'parcial';
          case 'Cancelado':
            return v.status == 'cancelado';
          default:
            return true;
        }
      }).toList();
    }

    if (formaPagamento != 'Todos') {
      lista = lista.where((v) {
        switch (formaPagamento) {
          case 'Dinheiro':
            return v.formaPagamento == 'dinheiro';
          case 'PIX':
            return v.formaPagamento == 'pix';
          case 'Cartão':
            return v.formaPagamento == 'cartao' ||
                v.formaPagamento == 'cartão' ||
                v.formaPagamento == 'credito' ||
                v.formaPagamento == 'credito_debito';
          case 'Crédito do Cliente':
            return v.isCredito;
          case 'Transferência':
            return v.formaPagamento == 'transferencia' ||
                v.formaPagamento == 'transferência';
          default:
            return true;
        }
      }).toList();
    }

    return lista;
  }

  static String formatarMoeda(double v) {
    return 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  static String formatarData(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }

  static String formatarDataHora(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
}

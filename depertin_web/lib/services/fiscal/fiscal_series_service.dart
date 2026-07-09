import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'fiscal_serie_model.dart';

/// Gerencia séries fiscais e numeração sequencial de NF-e por loja.
///
/// Cada loja tem seu próprio contador por série, garantindo que
/// nunca haja mistura de sequências entre lojistas diferentes.
abstract final class FiscalSeriesService {
  static const String _colecao = 'fiscal_series';
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Retorna a série ativa de uma loja para um tipo de documento.
  static Future<FiscalSerieModel?> obterSerieAtiva({
    required String storeId,
    String documentType = 'nfe',
    String serie = '1',
  }) async {
    final snap = await _db
        .collection(_colecao)
        .where('store_id', isEqualTo: storeId)
        .where('serie', isEqualTo: serie)
        .where('document_type', isEqualTo: documentType)
        .where('ativa', isEqualTo: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return FiscalSerieModel.fromFirestore(snap.docs.first);
  }

  /// Obtém o próximo número disponível e já reserva (incrementa).
  ///
  /// Usa transação Firestore para garantir atomicidade.
  /// Retorna {serie, numero}.
  static Future<({String serie, int numero})> reservarProximoNumero({
    required String storeId,
    String documentType = 'nfe',
    String serie = '1',
    String ambiente = 'sandbox',
  }) async {
    // Tenta encontrar série existente
    final existente = await obterSerieAtiva(
      storeId: storeId,
      documentType: documentType,
      serie: serie,
    );

    if (existente != null) {
      // Incrementa em transação
      return await _incrementarTransacao(existente.id, existente.proximoNumero);
    }

    // Cria nova série
    final novaSerie = FiscalSerieModel(
      id: '',
      storeId: storeId,
      serie: serie,
      documentType: documentType,
      proximoNumero: 1,
      ultimoNumeroUtilizado: 0,
      ambiente: ambiente,
      ativa: true,
    );

    final ref = _db.collection(_colecao).doc();
    await ref.set(novaSerie.toCreateMap());
    return (serie: serie, numero: 1);
  }

  /// Incrementa o contador em transação.
  static Future<({String serie, int numero})> _incrementarTransacao(
    String docId,
    int numeroAtual,
  ) async {
    int numeroReservado = numeroAtual;
    String serieReservada = '1';

    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(_db.collection(_colecao).doc(docId));
      if (!snap.exists) return;
      final data = snap.data()!;
      final prox = (data['proximo_numero'] as num?)?.toInt() ?? numeroAtual;
      final ser = data['serie'] as String? ?? '1';
      numeroReservado = prox;
      serieReservada = ser;
      transaction.update(snap.reference, {
        'proximo_numero': prox + 1,
        'ultimo_numero_utilizado': prox,
        'updated_at': FieldValue.serverTimestamp(),
      });
    });

    return (serie: serieReservada, numero: numeroReservado);
  }

  /// Marca um número como utilizado (após emissão bem-sucedida).
  static Future<void> confirmarNumeracao({
    required String storeId,
    required int numero,
    String documentType = 'nfe',
    String serie = '1',
  }) async {
    final existente = await obterSerieAtiva(
      storeId: storeId,
      documentType: documentType,
      serie: serie,
    );
    if (existente == null) return;

    if (numero > existente.ultimoNumeroUtilizado) {
      await _db.collection(_colecao).doc(existente.id).update({
        'ultimo_numero_utilizado': numero,
        'proximo_numero': FieldValue.increment(1),
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Stream em tempo real da série de uma loja.
  static Stream<FiscalSerieModel?> streamSerie({
    required String storeId,
    String documentType = 'nfe',
    String serie = '1',
  }) {
    return _db
        .collection(_colecao)
        .where('store_id', isEqualTo: storeId)
        .where('serie', isEqualTo: serie)
        .where('document_type', isEqualTo: documentType)
        .limit(1)
        .snapshots()
        .map((snap) =>
            snap.docs.isNotEmpty
                ? FiscalSerieModel.fromFirestore(snap.docs.first)
                : null);
  }

  /// Cria ou atualiza uma série.
  static Future<void> salvarSerie(FiscalSerieModel model) async {
    if (model.id.isNotEmpty) {
      await _db.collection(_colecao).doc(model.id).update(model.toMap());
    } else {
      await _db.collection(_colecao).add(model.toCreateMap());
    }
  }

  /// Lista todas as séries de uma loja.
  static Future<List<FiscalSerieModel>> listarSeries(String storeId) async {
    final snap = await _db
        .collection(_colecao)
        .where('store_id', isEqualTo: storeId)
        .orderBy('serie', descending: false)
        .get();
    return snap.docs.map(FiscalSerieModel.fromFirestore).toList();
  }
}

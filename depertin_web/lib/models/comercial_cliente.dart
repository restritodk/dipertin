import 'package:cloud_firestore/cloud_firestore.dart';

/// Cliente da gestão comercial da loja (`users/{lojaId}/clientes_comercial/{id}`).
class ComercialCliente {
  ComercialCliente({
    required this.id,
    required this.lojaId,
    required this.nome,
    this.telefone,
    this.whatsapp,
    this.cpf,
    this.rg,
    this.email,
    this.dataNascimento,
    this.cep,
    this.rua,
    this.numero,
    this.complemento,
    this.bairro,
    this.cidade,
    this.estado,
    this.codigoIbge,
    this.creditoHabilitado = false,
    this.limiteCredito = 0,
    this.creditoUtilizado = 0,
    this.diaVencimentoCredito,
    this.observacaoCredito,
    this.status = 'ativo',
    this.observacoes,
    this.cashback = 0,
    this.pendencias = const [],
    this.vip = false,
    this.createdAt,
    this.updatedAt,
    this.totalComprado = 0,
    this.ultimaCompra,
  });

  final String id;
  final String lojaId;
  final String nome;
  final String? telefone;
  final String? whatsapp;
  final String? cpf;
  final String? rg;
  final String? email;
  final DateTime? dataNascimento;
  final String? cep;
  final String? rua;
  final String? numero;
  final String? complemento;
  final String? bairro;
  final String? cidade;
  final String? estado;
  final String? codigoIbge;
  final bool creditoHabilitado;
  final double limiteCredito;
  final double creditoUtilizado;
  final int? diaVencimentoCredito;
  final String? observacaoCredito;
  final String status;
  final String? observacoes;
  final double cashback;
  final List<ComercialClientePendencia> pendencias;
  final bool vip;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Agregado de `pedidos` (não persistido no doc).
  final double totalComprado;
  final DateTime? ultimaCompra;

  double get creditoDisponivel => limiteCredito - creditoUtilizado;

  bool get temCredito =>
      creditoHabilitado && (limiteCredito > 0 || creditoUtilizado > 0);

  bool get temPendenciaAberta {
    final hoje = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    for (final p in pendencias) {
      if (p.paga) continue;
      final venc = DateTime(p.vencimento.year, p.vencimento.month, p.vencimento.day);
      if (!venc.isAfter(hoje)) return true;
    }
    return creditoUtilizado > limiteCredito && limiteCredito > 0;
  }

  String get statusExibicao {
    if (status == 'bloqueado') return 'bloqueado';
    if (temPendenciaAberta) return 'com_pendencia';
    if (status == 'inativo') return 'inativo';
    return 'ativo';
  }

  ComercialCliente copyWith({
    String? id,
    String? lojaId,
    String? nome,
    String? telefone,
    String? whatsapp,
    String? cpf,
    String? rg,
    String? email,
    DateTime? dataNascimento,
    String? cep,
    String? rua,
    String? numero,
    String? complemento,
    String? bairro,
    String? cidade,
    String? estado,
    String? codigoIbge,
    bool? creditoHabilitado,
    double? limiteCredito,
    double? creditoUtilizado,
    int? diaVencimentoCredito,
    String? observacaoCredito,
    String? status,
    String? observacoes,
    double? cashback,
    List<ComercialClientePendencia>? pendencias,
    bool? vip,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? totalComprado,
    DateTime? ultimaCompra,
  }) {
    return ComercialCliente(
      id: id ?? this.id,
      lojaId: lojaId ?? this.lojaId,
      nome: nome ?? this.nome,
      telefone: telefone ?? this.telefone,
      whatsapp: whatsapp ?? this.whatsapp,
      cpf: cpf ?? this.cpf,
      rg: rg ?? this.rg,
      email: email ?? this.email,
      dataNascimento: dataNascimento ?? this.dataNascimento,
      cep: cep ?? this.cep,
      rua: rua ?? this.rua,
      numero: numero ?? this.numero,
      complemento: complemento ?? this.complemento,
      bairro: bairro ?? this.bairro,
      cidade: cidade ?? this.cidade,
      estado: estado ?? this.estado,
      codigoIbge: codigoIbge ?? this.codigoIbge,
      creditoHabilitado: creditoHabilitado ?? this.creditoHabilitado,
      limiteCredito: limiteCredito ?? this.limiteCredito,
      creditoUtilizado: creditoUtilizado ?? this.creditoUtilizado,
      diaVencimentoCredito: diaVencimentoCredito ?? this.diaVencimentoCredito,
      observacaoCredito: observacaoCredito ?? this.observacaoCredito,
      status: status ?? this.status,
      observacoes: observacoes ?? this.observacoes,
      cashback: cashback ?? this.cashback,
      pendencias: pendencias ?? this.pendencias,
      vip: vip ?? this.vip,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      totalComprado: totalComprado ?? this.totalComprado,
      ultimaCompra: ultimaCompra ?? this.ultimaCompra,
    );
  }

  factory ComercialCliente.fromDoc(
    String id,
    String lojaId,
    Map<String, dynamic> d, {
    double totalComprado = 0,
    DateTime? ultimaCompra,
  }) {
    return ComercialCliente(
      id: id,
      lojaId: lojaId,
      nome: (d['nome'] ?? d['cliente_nome'] ?? 'Cliente').toString(),
      telefone: d['telefone']?.toString(),
      whatsapp: d['whatsapp']?.toString(),
      cpf: d['cpf']?.toString(),
      rg: d['rg']?.toString(),
      email: d['email']?.toString(),
      dataNascimento: _parseData(d['data_nascimento']),
      cep: d['cep']?.toString(),
      rua: d['rua']?.toString(),
      numero: d['numero']?.toString(),
      complemento: d['complemento']?.toString(),
      bairro: d['bairro']?.toString(),
      cidade: d['cidade']?.toString(),
      estado: d['estado']?.toString(),
      codigoIbge: d['codigo_ibge']?.toString(),
      creditoHabilitado: d['credito_habilitado'] == true,
      limiteCredito: _num(d['limite_credito']),
      creditoUtilizado: _num(d['credito_utilizado']),
      diaVencimentoCredito: _intOrNull(d['dia_vencimento_credito']),
      observacaoCredito: d['observacao_credito']?.toString(),
      status: (d['status'] ?? 'ativo').toString(),
      observacoes: d['observacoes']?.toString(),
      cashback: _num(d['cashback']),
      pendencias: _parsePendencias(d['pendencias']),
      vip: d['vip'] == true,
      createdAt: _parseTs(d['created_at'] ?? d['criado_em']),
      updatedAt: _parseTs(d['updated_at'] ?? d['atualizado_em']),
      totalComprado: totalComprado,
      ultimaCompra: ultimaCompra,
    );
  }

  Map<String, dynamic> toFirestore({bool criando = false}) {
    final map = <String, dynamic>{
      'loja_id': lojaId,
      'nome': nome.trim(),
      if (telefone != null && telefone!.trim().isNotEmpty) 'telefone': telefone!.trim(),
      if (whatsapp != null && whatsapp!.trim().isNotEmpty) 'whatsapp': whatsapp!.trim(),
      if (cpf != null && cpf!.trim().isNotEmpty) 'cpf': cpf!.trim(),
      if (rg != null && rg!.trim().isNotEmpty) 'rg': rg!.trim(),
      if (email != null && email!.trim().isNotEmpty) 'email': email!.trim(),
      if (dataNascimento != null)
        'data_nascimento': Timestamp.fromDate(dataNascimento!),
      if (cep != null && cep!.trim().isNotEmpty) 'cep': cep!.trim(),
      if (rua != null && rua!.trim().isNotEmpty) 'rua': rua!.trim(),
      if (numero != null && numero!.trim().isNotEmpty) 'numero': numero!.trim(),
      if (complemento != null && complemento!.trim().isNotEmpty)
        'complemento': complemento!.trim(),
      if (bairro != null && bairro!.trim().isNotEmpty) 'bairro': bairro!.trim(),
      if (cidade != null && cidade!.trim().isNotEmpty) 'cidade': cidade!.trim(),
      if (estado != null && estado!.trim().isNotEmpty) 'estado': estado!.trim(),
      if (codigoIbge != null && codigoIbge!.trim().isNotEmpty)
        'codigo_ibge': codigoIbge!.trim(),
      'credito_habilitado': creditoHabilitado,
      'limite_credito': limiteCredito,
      'credito_utilizado': creditoUtilizado,
      if (diaVencimentoCredito != null) 'dia_vencimento_credito': diaVencimentoCredito,
      if (observacaoCredito != null && observacaoCredito!.trim().isNotEmpty)
        'observacao_credito': observacaoCredito!.trim(),
      'status': status,
      if (observacoes != null && observacoes!.trim().isNotEmpty)
        'observacoes': observacoes!.trim(),
      'cashback': cashback,
      'pendencias': pendencias.map((p) => p.toMap()).toList(),
      'vip': vip,
      'updated_at': FieldValue.serverTimestamp(),
    };
    if (criando) {
      map['created_at'] = FieldValue.serverTimestamp();
    }
    return map;
  }

  /// Payload para seleção no PDV (F3).
  Map<String, dynamic> toPdvMap() => {
        'id': id,
        'nome': nome,
        if (telefone != null) 'telefone': telefone,
        if (cpf != null) 'cpf': cpf,
        'origem': 'clientes_comercial',
        'credito_habilitado': creditoHabilitado,
        'limite_credito': limiteCredito,
        'credito_utilizado': creditoUtilizado,
        'credito_disponivel': creditoDisponivel,
        if (diaVencimentoCredito != null)
          'dia_vencimento_credito': diaVencimentoCredito,
      };

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
  }

  static int? _intOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static DateTime? _parseData(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.tryParse(v?.toString() ?? '');
  }

  static DateTime? _parseTs(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.tryParse(v?.toString() ?? '');
  }

  static List<ComercialClientePendencia> _parsePendencias(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => ComercialClientePendencia.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }
}

class ComercialClientePendencia {
  const ComercialClientePendencia({
    required this.valor,
    required this.vencimento,
    this.paga = false,
    this.pagoEm,
    this.descricao,
  });

  final double valor;
  final DateTime vencimento;
  final bool paga;
  final DateTime? pagoEm;
  final String? descricao;

  factory ComercialClientePendencia.fromMap(Map<String, dynamic> m) {
    DateTime parseTs(dynamic v) {
      if (v is Timestamp) return v.toDate();
      return DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();
    }

    return ComercialClientePendencia(
      valor: ComercialCliente._num(m['valor']),
      vencimento: parseTs(m['vencimento']),
      paga: m['paga'] == true,
      pagoEm: m['pago_em'] != null ? parseTs(m['pago_em']) : null,
      descricao: m['descricao']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'valor': valor,
        'vencimento': Timestamp.fromDate(vencimento),
        'paga': paga,
        if (pagoEm != null) 'pago_em': Timestamp.fromDate(pagoEm!),
        if (descricao != null) 'descricao': descricao,
      };
}

/// KPIs da listagem de clientes.
class ComercialClientesIndicadores {
  const ComercialClientesIndicadores({
    required this.total,
    required this.ativos,
    required this.comCredito,
    required this.comPendencias,
  });

  final int total;
  final int ativos;
  final int comCredito;
  final int comPendencias;

  double pct(int parte) => total == 0 ? 0 : (parte / total) * 100;
}

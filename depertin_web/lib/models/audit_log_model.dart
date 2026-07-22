import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/audit_visual.dart';

/// Modelo de log de auditoria (painel web).
///
/// Reflete o shape retornado pelo callable `auditLogsListarEventos`. Apenas
/// staff (master/master_city) lê — por isso email vem em claro.
class AuditLog {
  final String id;
  final DateTime? criadoEm;
  final String acao;
  final String categoria;
  final String origem;
  final String? atorUid;
  final String? atorEmail;
  final String? atorNome;
  final String? atorRole;
  final String? modulo;
  final String? tela;
  final String? entityType;
  final String? entityId;
  final String severidade; // info|atencao|critica
  final String resultado; // sucesso|erro|alerta
  final String? codigoErro;
  final String? mensagemErro;
  final String? ip;
  final String? userAgent;
  final String? plataforma;
  final Map<String, dynamic>? diff;
  final Map<String, dynamic>? mudancas;
  final Map<String, dynamic>? detalheExtras;

  const AuditLog({
    required this.id,
    required this.acao,
    required this.categoria,
    required this.origem,
    this.criadoEm,
    this.atorUid,
    this.atorEmail,
    this.atorNome,
    this.atorRole,
    this.modulo,
    this.tela,
    this.entityType,
    this.entityId,
    this.severidade = 'info',
    this.resultado = 'sucesso',
    this.codigoErro,
    this.mensagemErro,
    this.ip,
    this.userAgent,
    this.plataforma,
    this.diff,
    this.mudancas,
    this.detalheExtras,
  });

  factory AuditLog.fromMap(Map<String, dynamic> m) {
    DateTime? criado;
    final ce = m['criado_em'];
    if (ce is Timestamp) {
      criado = ce.toDate();
    } else if (ce is String) {
      criado = DateTime.tryParse(ce);
    } else if (ce is Map && ce['_seconds'] != null) {
      criado = DateTime.fromMillisecondsSinceEpoch(
        (ce['_seconds'] as int) * 1000,
      );
    }
    Map<String, dynamic>? _asMap(dynamic v) {
      if (v is Map) return Map<String, dynamic>.from(v);
      return null;
    }
    return AuditLog(
      id: (m['id'] ?? '').toString(),
      criadoEm: criado,
      acao: (m['acao'] ?? '').toString(),
      categoria: (m['categoria'] ?? '').toString(),
      origem: (m['origem'] ?? '').toString(),
      atorUid: m['ator_uid']?.toString(),
      // Fallback: aceita tanto `ator_email` (novo) quanto
      // `ator_email_mascarado` (caso logs antigos do backend).
      atorEmail: m['ator_email']?.toString() ??
          m['ator_email_mascarado']?.toString(),
      atorNome: m['ator_nome']?.toString(),
      atorRole: m['ator_role']?.toString(),
      modulo: m['modulo']?.toString(),
      tela: m['tela']?.toString(),
      entityType: m['entity_type']?.toString(),
      entityId: m['entity_id']?.toString(),
      severidade: (m['severidade'] ?? 'info').toString(),
      resultado: (m['resultado'] ?? 'sucesso').toString(),
      codigoErro: m['codigo_erro']?.toString(),
      mensagemErro: m['mensagem_erro']?.toString(),
      ip: m['ip']?.toString(),
      userAgent: m['user_agent']?.toString(),
      plataforma: m['plataforma']?.toString(),
      diff: _asMap(m['diff']),
      mudancas: _asMap(m['mudancas']),
      detalheExtras: _asMap(m['detalhe_extras']),
    );
  }

  /// Resumo visual para a tabela.
  String get descricaoResumida {
    return AuditVisual.formatarNomeAcao(acao);
  }

  /// Identifica o tipo de "ator" para fins de filtro de categoria.
  String get tipoAtor {
    final r = (atorRole ?? '').toLowerCase();
    if (r == 'cliente') return 'cliente';
    if (r == 'lojista') return 'lojista';
    if (r == 'entregador') return 'entregador';
    if (r == 'master' || r == 'master_city' || r == 'superadmin' || r == 'super_admin') {
      return 'admin';
    }
    // Inferir pela origem
    final o = origem.toLowerCase();
    if (o.contains('painel')) return 'admin';
    return 'desconhecido';
  }

  /// Nome de exibição do usuário para a tabela.
  /// Prioridade: atorNome → atorEmail → "Usuário não identificado"
  /// (UID nunca aparece como identificação principal).
  String get nomeExibicao {
    if (atorNome != null && atorNome!.isNotEmpty) return atorNome!;
    if (atorEmail != null && atorEmail!.isNotEmpty) return atorEmail!;
    return 'Usuário não identificado';
  }

  /// Perfil amigável (ex.: "Administrador Master" em vez de "admin").
  String get perfilAmigavel => AuditVisual.perfilAmigavel(atorRole);

  /// Perfil curto para coluna Categoria (ex.: "Admin", "Lojista").
  String get perfilCurto => AuditVisual.perfilCurto(atorRole);
}

/// Resumo de usuário (retornado por `auditLogsPesquisarUsuarios`).
class AuditUser {
  final String uid;
  final String? nome;
  final String? emailMascarado;
  final String? documentoMascarado;
  final String? telefoneMascarado;
  final String? role;
  final String? cidade;
  final String? lojaNome;
  final String? status;

  const AuditUser({
    required this.uid,
    this.nome,
    this.emailMascarado,
    this.documentoMascarado,
    this.telefoneMascarado,
    this.role,
    this.cidade,
    this.lojaNome,
    this.status,
  });

  factory AuditUser.fromMap(Map<String, dynamic> m) {
    return AuditUser(
      uid: (m['uid'] ?? '').toString(),
      nome: m['nome']?.toString(),
      emailMascarado: m['email_mascarado']?.toString(),
      documentoMascarado: m['documento_mascarado']?.toString(),
      telefoneMascarado: m['telefone_mascarado']?.toString(),
      role: m['role']?.toString(),
      cidade: m['cidade']?.toString(),
      lojaNome: m['loja_nome']?.toString(),
      status: m['status']?.toString(),
    );
  }
}

/// Estatísticas para os KPI cards (retornado por `auditLogsEstatisticas`).
class AuditStats {
  final int total;
  final int hoje;
  final int sucesso;
  final int erro;
  final int alerta;
  final int info;
  final int atencao;
  final int critica;
  final int tentativasLogin;
  final int usuariosUnicos;
  final int administrativas;

  const AuditStats({
    this.total = 0,
    this.hoje = 0,
    this.sucesso = 0,
    this.erro = 0,
    this.alerta = 0,
    this.info = 0,
    this.atencao = 0,
    this.critica = 0,
    this.tentativasLogin = 0,
    this.usuariosUnicos = 0,
    this.administrativas = 0,
  });

  factory AuditStats.fromMap(Map<String, dynamic> m) {
    int _i(String k) {
      final v = m[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }
    return AuditStats(
      total: _i('total'),
      hoje: _i('hoje'),
      sucesso: _i('sucesso'),
      erro: _i('erro'),
      alerta: _i('alerta'),
      info: _i('info'),
      atencao: _i('atencao'),
      critica: _i('critica'),
      tentativasLogin: _i('tentativas_login'),
      usuariosUnicos: _i('usuarios_unicos'),
      administrativas: _i('administrativas'),
    );
  }
}

/// Categorias de ator que a UI pode filtrar.
import 'audit_log_model.dart' show AuditLog;

class AuditCategoria {
  static const String cliente = 'cliente';
  static const String lojista = 'lojista';
  static const String entregador = 'entregador';
  static const String admin = 'admin';
  static const List<String> todas = [cliente, lojista, entregador, admin];

  static String label(String c) {
    switch (c) {
      case cliente:
        return 'Clientes';
      case lojista:
        return 'Lojistas';
      case entregador:
        return 'Entregadores';
      case admin:
        return 'Administradores';
      default:
        return c;
    }
  }

  static IconDataForCategoria? iconFor(String c) {
    switch (c) {
      case cliente:
        return IconDataForCategoria.people();
      case lojista:
        return IconDataForCategoria.store();
      case entregador:
        return IconDataForCategoria.delivery();
      case admin:
        return IconDataForCategoria.admin();
      default:
        return null;
    }
  }
}

/// Sentinel para ícone (Material) por categoria de ator.
class IconDataForCategoria {
  final String materialName;
  const IconDataForCategoria(this.materialName);
  factory IconDataForCategoria.people() => const IconDataForCategoria('people');
  factory IconDataForCategoria.store() => const IconDataForCategoria('store');
  factory IconDataForCategoria.delivery() => const IconDataForCategoria('delivery_dining');
  factory IconDataForCategoria.admin() => const IconDataForCategoria('shield');
}

/// Faixas de período rápido.
class AuditPeriodo {
  static const String tudo = 'tudo';
  static const String hoje = 'hoje';
  static const String seteDias = '7d';
  static const String trintaDias = '30d';
  static const String personalizado = 'personalizado';

  static String label(String p) {
    switch (p) {
      case tudo:
        return 'Tudo';
      case hoje:
        return 'Hoje';
      case seteDias:
        return 'Últimos 7 dias';
      case trintaDias:
        return 'Últimos 30 dias';
      case personalizado:
        return 'Personalizado';
      default:
        return p;
    }
  }

  /// Calcula os timestamps (ms) a partir do período.
  static ({int? inicio, int? fim}) range(String p) {
    final agora = DateTime.now();
    switch (p) {
      case hoje:
        final inicio = DateTime(agora.year, agora.month, agora.day);
        return (inicio: inicio.millisecondsSinceEpoch, fim: null);
      case seteDias:
        final inicio = agora.subtract(const Duration(days: 7));
        return (inicio: inicio.millisecondsSinceEpoch, fim: null);
      case trintaDias:
        final inicio = agora.subtract(const Duration(days: 30));
        return (inicio: inicio.millisecondsSinceEpoch, fim: null);
      default:
        return (inicio: null, fim: null);
    }
  }
}

/// Modelo de filtros para a tela de auditoria.
class AuditFiltros {
  final String periodo; // tudo|hoje|7d|30d|personalizado
  final String? atorUid;
  final String? categoriaAtor; // cliente|lojista|entregador|admin
  final String? categoria; // categoria do log
  final String? acao;
  final String? modulo;
  final String? resultado; // sucesso|erro|alerta
  final String? severidade; // info|atencao|critica
  final String? origem; // cloud_functions|app:android|app:ios|painel_web
  final DateTime? dataInicio;
  final DateTime? dataFim;

  const AuditFiltros({
    this.periodo = AuditPeriodo.trintaDias,
    this.atorUid,
    this.categoriaAtor,
    this.categoria,
    this.acao,
    this.modulo,
    this.resultado,
    this.severidade,
    this.origem,
    this.dataInicio,
    this.dataFim,
  });

  AuditFiltros copyWith({
    String? periodo,
    Object? atorUid = _sentinel,
    Object? categoriaAtor = _sentinel,
    Object? categoria = _sentinel,
    Object? acao = _sentinel,
    Object? modulo = _sentinel,
    Object? resultado = _sentinel,
    Object? severidade = _sentinel,
    Object? origem = _sentinel,
    Object? dataInicio = _sentinel,
    Object? dataFim = _sentinel,
  }) {
    return AuditFiltros(
      periodo: periodo ?? this.periodo,
      atorUid: identical(atorUid, _sentinel) ? this.atorUid : atorUid as String?,
      categoriaAtor: identical(categoriaAtor, _sentinel)
          ? this.categoriaAtor
          : categoriaAtor as String?,
      categoria:
          identical(categoria, _sentinel) ? this.categoria : categoria as String?,
      acao: identical(acao, _sentinel) ? this.acao : acao as String?,
      modulo: identical(modulo, _sentinel) ? this.modulo : modulo as String?,
      resultado:
          identical(resultado, _sentinel) ? this.resultado : resultado as String?,
      severidade:
          identical(severidade, _sentinel) ? this.severidade : severidade as String?,
      origem: identical(origem, _sentinel) ? this.origem : origem as String?,
      dataInicio: identical(dataInicio, _sentinel)
          ? this.dataInicio
          : dataInicio as DateTime?,
      dataFim: identical(dataFim, _sentinel) ? this.dataFim : dataFim as DateTime?,
    );
  }

  /// Serializa para o payload do callable.
  Map<String, dynamic> toCallablePayload() {
    int? dataInicioMs;
    int? dataFimMs;
    if (periodo != AuditPeriodo.tudo && periodo != AuditPeriodo.personalizado) {
      final r = AuditPeriodo.range(periodo);
      dataInicioMs = r.inicio;
    } else if (periodo == AuditPeriodo.personalizado) {
      dataInicioMs = dataInicio?.millisecondsSinceEpoch;
      dataFimMs = dataFim?.millisecondsSinceEpoch;
    }
    return {
      if (atorUid != null) 'ator_uid': atorUid,
      if (categoria != null) 'categoria': categoria,
      if (modulo != null) 'modulo': modulo,
      if (resultado != null) 'resultado': resultado,
      if (severidade != null) 'severidade': severidade,
      if (acao != null) 'acao': acao,
      if (origem != null) 'origem': origem,
      if (dataInicioMs != null) 'data_inicio_ms': dataInicioMs,
      if (dataFimMs != null) 'data_fim_ms': dataFimMs,
    };
  }

  static const Object _sentinel = Object();

  static const empty = AuditFiltros();
}

/// Resposta paginada do callable `auditLogsListarEventos`.
class AuditPage {
  final List<AuditLog> items;
  final bool hasMore;
  final String? lastDocId;
  final String? firstDocId;

  const AuditPage({
    required this.items,
    required this.hasMore,
    this.lastDocId,
    this.firstDocId,
  });
}

/// Categorias de log pré-definidas para o select de filtro.
class AuditCategoriaLog {
  static const String pedido = 'pedido';
  static const String sessao = 'sessao';
  static const String financeiro = 'financeiro';
  static const String assinatura = 'assinatura';
  static const String fiscal = 'fiscal';
  static const String conta = 'conta';
  static const String admin = 'admin';
  static const String marketing = 'marketing';
  static const String suporte = 'suporte';
  static const String sistema = 'sistema';
  static const String app = 'app';
  static const String notificacao = 'notificacao';
  static const String erroApp = 'erro_app';

  static const List<String> todas = [
    pedido, sessao, financeiro, assinatura, fiscal, conta,
    admin, marketing, suporte, sistema, app, notificacao, erroApp,
  ];

  static String label(String c) {
    switch (c) {
      case pedido:
        return 'Pedidos';
      case sessao:
        return 'Sessão';
      case financeiro:
        return 'Financeiro';
      case assinatura:
        return 'Assinaturas';
      case fiscal:
        return 'Fiscal';
      case conta:
        return 'Conta';
      case admin:
        return 'Administração';
      case marketing:
        return 'Marketing';
      case suporte:
        return 'Suporte';
      case sistema:
        return 'Sistema';
      case app:
        return 'App';
      case notificacao:
        return 'Notificações';
      case erroApp:
        return 'Erros do app';
      default:
        return c;
    }
  }
}

/// Lista de origens conhecidas.
class AuditOrigem {
  static const String cloudFunctions = 'cloud_functions';
  static const String painelWeb = 'painel_web';
  static const String appAndroid = 'app:android';
  static const String appIos = 'app:ios';

  static String label(String o) {
    switch (o) {
      case cloudFunctions:
        return 'Cloud Functions';
      case painelWeb:
        return 'Painel web';
      case appAndroid:
        return 'App Android';
      case appIos:
        return 'App iOS';
      default:
        if (o.startsWith('app:')) return 'App ${o.substring(4)}';
        return o;
    }
  }
}

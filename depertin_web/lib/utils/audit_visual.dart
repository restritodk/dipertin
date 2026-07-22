import 'package:flutter/material.dart';
import '../theme/painel_admin_theme.dart';

/// Cores e labels para severidade e resultado de auditoria.
abstract final class AuditVisual {
  /// Cor principal para badge de severidade.
  static Color corSeveridade(String? s) {
    switch (s) {
      case 'critica':
        return PainelAdminTheme.roxoEscuro;
      case 'atencao':
        return PainelAdminTheme.laranja;
      case 'info':
      default:
        return const Color(0xFF0EA5E9); // infoBlue
    }
  }

  /// Cor de fundo suave para badge de severidade.
  static Color fundoSeveridade(String? s) {
    return corSeveridade(s).withValues(alpha: 0.12);
  }

  /// Cor para badge de resultado.
  static Color corResultado(String? r) {
    switch (r) {
      case 'erro':
        return PainelAdminTheme.errorRedAlt;
      case 'alerta':
        return PainelAdminTheme.laranja;
      case 'sucesso':
      default:
        return const Color(0xFF059669); // successGreenAlt
    }
  }

  /// Cor de fundo para badge de resultado.
  static Color fundoResultado(String? r) {
    return corResultado(r).withValues(alpha: 0.12);
  }

  /// Ícone sugerido por severidade.
  static IconData iconSeveridade(String? s) {
    switch (s) {
      case 'critica':
        return Icons.report_gmailerrorred_rounded;
      case 'atencao':
        return Icons.warning_amber_rounded;
      case 'info':
      default:
        return Icons.info_outline_rounded;
    }
  }

  /// Ícone sugerido por resultado.
  static IconData iconResultado(String? r) {
    switch (r) {
      case 'erro':
        return Icons.error_outline_rounded;
      case 'alerta':
        return Icons.warning_amber_rounded;
      case 'sucesso':
      default:
        return Icons.check_circle_outline_rounded;
    }
  }

  /// Label amigável.
  static String labelSeveridade(String? s) {
    switch (s) {
      case 'critica':
        return 'Crítica';
      case 'atencao':
        return 'Atenção';
      case 'info':
      default:
        return 'Informação';
    }
  }

  /// Label amigável para resultado.
  static String labelResultado(String? r) {
    switch (r) {
      case 'erro':
        return 'Erro';
      case 'alerta':
        return 'Alerta';
      case 'sucesso':
      default:
        return 'Sucesso';
    }
  }

  /// Ícones por categoria de ator.
  static IconData iconCategoria(String? cat) {
    switch (cat) {
      case 'cliente':
        return Icons.person_outline_rounded;
      case 'lojista':
        return Icons.storefront_outlined;
      case 'entregador':
        return Icons.delivery_dining_rounded;
      case 'admin':
        return Icons.shield_outlined;
      default:
        return Icons.help_outline_rounded;
    }
  }

  /// Cores para cards de categoria de ator.
  static Color corCategoria(String? cat) {
    switch (cat) {
      case 'cliente':
        return const Color(0xFF0EA5E9); // infoBlue
      case 'lojista':
        return PainelAdminTheme.laranja;
      case 'entregador':
        return PainelAdminTheme.roxo;
      case 'admin':
        return PainelAdminTheme.roxoEscuro;
      default:
        return PainelAdminTheme.textoSecundario;
    }
  }

  /// Mapa centralizado de códigos de ação → texto amigável em português.
  static const Map<String, String> _mapaAcoes = {
    // Auditoria
    'auditoria_acesso': 'Acesso ao módulo de auditoria',
    'auditoria_exportacao': 'Exportação de registros de auditoria',
    // Sessão / Login
    'login_sessao_painel_web': 'Login no painel administrativo',
    'login_sessao_app': 'Login no aplicativo',
    'login_sucesso': 'Login realizado com sucesso',
    'login_falha': 'Falha na tentativa de login',
    'logout_sucesso': 'Logout realizado',
    'login_sessao_mobile_sucesso': 'Login no aplicativo',
    'login_sessao_mobile_falha': 'Falha no login do aplicativo',
    // Pedidos
    'pedido_criado': 'Criação de pedido',
    'pedido_status_alterado': 'Alteração do status do pedido',
    'alterar_status_entrega': 'Alteração do status da entrega',
    'criar_pedido': 'Criação de pedido',
    'cancelar_pedido': 'Cancelamento de pedido',
    'encomenda_status_alterado': 'Alteração na negociação de encomenda',
    // Financeiro
    'estorno_registrado': 'Registro de estorno',
    'saque_solicitado': 'Solicitação de saque',
    'saque_status_alterado': 'Alteração no status do saque',
    'gateway_pagamento_criado': 'Cadastro de gateway de pagamento',
    'gateway_pagamento_alterado': 'Alteração de gateway de pagamento',
    // Assinaturas
    'assinatura_plano_criada': 'Criação de plano de assinatura',
    'assinatura_plano_alterado': 'Alteração de plano de assinatura',
    // Fiscal
    'fiscal_integracao_criada': 'Integração fiscal cadastrada',
    'fiscal_integracao_alterada': 'Alteração na integração fiscal',
    // Conta / Usuário
    'usuario_excluido': 'Exclusão de conta de usuário',
    'usuario_bloqueado': 'Bloqueio de usuário',
    'usuario_status_cadastro_alterado': 'Alteração de status de cadastro',
    'conta_excluida': 'Exclusão de conta',
    // Marketing
    'cupom_criado': 'Criação de cupom',
    'cupom_alterado': 'Alteração de cupom',
    'cupom_excluido': 'Exclusão de cupom',
    // Suporte
    'suporte_ticket_criado': 'Abertura de ticket de suporte',
    'suporte_ticket_status_alterado': 'Alteração no ticket de suporte',
    // Sistema
    'notificacao_fcm_registrada': 'Registro de notificação push',
    'flutter_erro_nao_tratado': 'Erro não tratado no aplicativo',
  };

  /// Converte código técnico da ação em texto amigável em português.
  ///
  /// Usa o mapa centralizado. Se a ação não estiver mapeada, aplica fallback:
  /// substitui `_` por espaço e capitaliza a primeira letra.
  static String formatarNomeAcao(String acao) {
    if (acao.isEmpty) return 'Evento';
    final amigavel = _mapaAcoes[acao];
    if (amigavel != null) return amigavel;
    // Fallback: substituir _ por espaço, capitalizar primeira letra
    final partes = acao.split('_').where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return 'Evento';
    // Capitalizar cada parte
    final capitalizadas = partes.map((p) {
      if (p.length <= 1) return p.toUpperCase();
      return p[0].toUpperCase() + p.substring(1);
    }).join(' ');
    return capitalizadas;
  }

  /// Retorna rótulo de perfil amigável a partir do role armazenado.
  static String perfilAmigavel(String? role) {
    switch (role?.toLowerCase()) {
      case 'master':
        return 'Administrador Master';
      case 'master_city':
        return 'Administrador da Cidade';
      case 'superadmin':
      case 'super_admin':
        return 'Super Administrador';
      case 'lojista':
        return 'Lojista';
      case 'entregador':
        return 'Entregador';
      case 'cliente':
        return 'Cliente';
      case 'sistema':
        return 'Sistema';
      default:
        return role ?? '—';
    }
  }

  /// Versão curta do perfil para a coluna Categoria da tabela.
  static String perfilCurto(String? role) {
    switch (role?.toLowerCase()) {
      case 'master':
      case 'master_city':
      case 'superadmin':
      case 'super_admin':
        return 'Admin';
      case 'lojista':
        return 'Lojista';
      case 'entregador':
        return 'Entregador';
      case 'cliente':
        return 'Cliente';
      case 'sistema':
        return 'Sistema';
      default:
        return role ?? '—';
    }
  }
}

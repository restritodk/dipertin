/// Códigos padronizados dos módulos do sistema de assinaturas.
///
/// Usados em:
/// - `assinaturas_modulos/{id}.codigo` — catálogo de módulos
/// - `modulos_planos/{id}.modulos` — lista de módulos habilitados em cada plano
/// - Filtros de permissão nas telas e serviços
abstract final class ModuloCodigos {
  ModuloCodigos._();

  /// Módulo Gestão Comercial (crediário, clientes, PDV, recebimentos).
  static const String gestaoComercial = 'gestao_comercial';

  /// Módulo de emissão de NF-e / NFC-e / NFS-e.
  ///
  /// Quando habilitado em um plano (`modulos_planos/{id}.modulos`),
  /// o lojista pode:
  /// - Contratar planos de emissão de NF-e (`planos_emissao_nfe`)
  /// - Utilizar a infraestrutura fiscal configurada pelo admin
  /// - Emitir notas fiscais pelo PDV e Gestão Comercial
  static const String emissaoNfe = 'emissao_nfe';

  /// Lista de todos os códigos de módulo conhecidos.
  static const List<String> todos = [
    gestaoComercial,
    emissaoNfe,
  ];
}

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter/foundation.dart';



import '../constants/modulo_codigos.dart';
import '../models/cliente_assinatura_model.dart';
import '../models/modulo_config_model.dart';



/// Contexto carregado uma vez para validar acesso ao Gestão Comercial.

class AssinaturaGestaoComercialContexto {

  const AssinaturaGestaoComercialContexto({

    required this.planosPorId,

    required this.planosGestaoIds,

    required this.modulosPorNome,

    required this.modulosPorId,

  });



  final Map<String, Map<String, dynamic>> planosPorId;

  final Set<String> planosGestaoIds;

  final Map<String, ModuloConfigModel> modulosPorNome;

  final Map<String, ModuloConfigModel> modulosPorId;

}



/// Regras compartilhadas entre sidebar, upsell e bloqueio.

abstract final class AssinaturaGestaoComercialService {

  static String _normalizar(String input) {

    return input

        .toLowerCase()

        .replaceAll('ã', 'a')

        .replaceAll('á', 'a')

        .replaceAll('â', 'a')

        .replaceAll('ç', 'c')

        .replaceAll('õ', 'o')

        .replaceAll('ó', 'o')

        .replaceAll(' ', '_')

        .replaceAll('-', '_');

  }



  /// Detecta se um texto/código/nome representa o módulo Gestão Comercial.

  static bool textoIndicaGestaoComercial(String? raw) {

    if (raw == null || raw.trim().isEmpty) return false;



    final normalizado = _normalizar(raw.trim());

    if (normalizado.contains('gestao_comercial')) return true;

    if (normalizado.contains('gestao') && normalizado.contains('comercial')) {

      return true;

    }

    if (normalizado == 'gc' || normalizado == 'comercial') return true;



    final lower = raw.toLowerCase();

    if (lower.contains('gest') && lower.contains('comercial')) return true;



    return false;

  }



  static bool _moduloConfigEhGestao(ModuloConfigModel? mod) {

    if (mod == null) return false;

    return textoIndicaGestaoComercial(mod.codigo) ||

        textoIndicaGestaoComercial(mod.nome);

  }



  static bool _moduloReferenciaEhGestao(

    String? ref,

    AssinaturaGestaoComercialContexto ctx,

  ) {

    if (ref == null || ref.trim().isEmpty) return false;

    final chave = ref.trim();

    if (textoIndicaGestaoComercial(chave)) return true;

    if (_moduloConfigEhGestao(ctx.modulosPorNome[chave])) return true;

    if (_moduloConfigEhGestao(ctx.modulosPorId[chave])) return true;

    return false;

  }



  static bool planoDocEhGestaoComercial(

    Map<String, dynamic> data, {

    required AssinaturaGestaoComercialContexto ctx,

  }) {

    final mv = data['modulo_vinculado']?.toString() ?? '';

    if (_moduloReferenciaEhGestao(mv, ctx)) return true;



    final modulos = data['modulos'];

    if (modulos is List) {

      for (final item in modulos) {

        if (_moduloReferenciaEhGestao(item.toString(), ctx)) return true;

      }

    }



    return false;

  }



  /// Plano legado criado antes do multi-select de módulos (sem metadados).

  static bool planoDocEhLegadoSemModulos(Map<String, dynamic> data) {

    final mv = data['modulo_vinculado']?.toString().trim() ?? '';

    final modulos = data['modulos'];

    final listaVazia = modulos is! List || modulos.isEmpty;

    return listaVazia && mv.isEmpty;

  }



  /// Resolve o ID do documento em `modulos_planos` a partir da assinatura.

  static String? resolverPlanoDocId(

    ClienteAssinaturaModel assinatura,

    AssinaturaGestaoComercialContexto ctx,

  ) {

    final planId = assinatura.planId.trim();

    if (planId.isNotEmpty && ctx.planosPorId.containsKey(planId)) {

      return planId;

    }



    final alvoNome = _normalizar(assinatura.planName);

    if (alvoNome.isNotEmpty) {

      for (final entry in ctx.planosPorId.entries) {

        final nomePlano = _normalizar(entry.value['nome']?.toString() ?? '');

        if (nomePlano.isNotEmpty && nomePlano == alvoNome) {

          return entry.key;

        }

      }

    }



    if (planId.isNotEmpty) {

      for (final entry in ctx.planosPorId.entries) {

        final nomePlano = _normalizar(entry.value['nome']?.toString() ?? '');

        if (nomePlano.isNotEmpty && nomePlano == _normalizar(planId)) {

          return entry.key;

        }

      }

    }



    return null;

  }



  static bool assinaturaEhGestaoComercial(

    ClienteAssinaturaModel assinatura,

    AssinaturaGestaoComercialContexto ctx,

  ) {

    final planoDocId = resolverPlanoDocId(assinatura, ctx);

    if (planoDocId != null) {

      // Plano contratado existe no catálogo ativo → libera Gestão Comercial.

      return true;

    }



    if (ctx.planosGestaoIds.contains(assinatura.planId)) return true;



    for (final mod in assinatura.modulosExtras) {

      if (_moduloReferenciaEhGestao(mod, ctx)) return true;

    }



    return false;

  }



  static bool assinaturaTemAcessoGestao(ClienteAssinaturaModel assinatura) {
    if (assinatura.status == 'suspenso' ||
        assinatura.status == 'cancelado' ||
        assinatura.status == 'pagamento_pendente') {
      return false;
    }

    if (assinatura.status == 'ativo') return true;

    return assinatura.statusExibicao == 'ativo' ||

        assinatura.statusExibicao == 'vencer_em_breve';

  }



  static Future<AssinaturaGestaoComercialContexto> carregarContexto() async {

    final db = FirebaseFirestore.instance;

    final snaps = await Future.wait([

      db.collection('modulos_planos').where('ativo', isEqualTo: true).get(),

      db.collection('assinaturas_modulos').get(),

    ]);



    final planosSnap = snaps[0];

    final modulosSnap = snaps[1];



    final modulosPorNome = <String, ModuloConfigModel>{};

    final modulosPorId = <String, ModuloConfigModel>{};

    for (final doc in modulosSnap.docs) {

      final mod = ModuloConfigModel.fromFirestore(doc);

      modulosPorId[mod.id] = mod;

      modulosPorNome[mod.nome] = mod;

      if (mod.codigo.trim().isNotEmpty) {

        modulosPorNome[mod.codigo] = mod;

      }

    }



    final ctxBase = AssinaturaGestaoComercialContexto(

      planosPorId: const {},

      planosGestaoIds: const {},

      modulosPorNome: modulosPorNome,

      modulosPorId: modulosPorId,

    );



    final planosPorId = <String, Map<String, dynamic>>{};

    final planosGestaoIds = <String>{};



    for (final doc in planosSnap.docs) {

      final data = doc.data();

      planosPorId[doc.id] = data;



      if (planoDocEhGestaoComercial(data, ctx: ctxBase) ||

          planoDocEhLegadoSemModulos(data)) {

        planosGestaoIds.add(doc.id);

      } else {

        // Catálogo `modulos_planos` só vende assinaturas do painel GC.

        planosGestaoIds.add(doc.id);

      }

    }



    return AssinaturaGestaoComercialContexto(

      planosPorId: planosPorId,

      planosGestaoIds: planosGestaoIds,

      modulosPorNome: modulosPorNome,

      modulosPorId: modulosPorId,

    );

  }



  static List<ClienteAssinaturaModel> filtrarAssinaturasGestao(

    List<ClienteAssinaturaModel> assinaturas,

    AssinaturaGestaoComercialContexto ctx,

  ) {

    return assinaturas

        .where((a) => assinaturaEhGestaoComercial(a, ctx))

        .toList();

  }



  /// Assinatura ativa com acesso ao GC (para rodapé da sidebar).

  static ClienteAssinaturaModel? assinaturaAtivaGestao(

    List<ClienteAssinaturaModel> assinaturas,

    AssinaturaGestaoComercialContexto ctx,

  ) {

    ClienteAssinaturaModel? melhor;

    for (final assinatura in filtrarAssinaturasGestao(assinaturas, ctx)) {

      if (!assinaturaTemAcessoGestao(assinatura)) continue;

      melhor ??= assinatura;

      if (assinatura.status == 'ativo') return assinatura;

    }

    return melhor;

  }



  static void logDebugContexto(

    AssinaturaGestaoComercialContexto ctx,

    List<ClienteAssinaturaModel> assinaturas,

  ) {

    if (!kDebugMode) return;

    final gestao =

        filtrarAssinaturasGestao(assinaturas, ctx);

    debugPrint(

      '[GestaoComercial] planos=${ctx.planosPorId.length} '

      'planosGestao=${ctx.planosGestaoIds.length} '

      'assinaturas=${assinaturas.length} assinaturasGestao=${gestao.length}',

    );

    for (final a in assinaturas) {

      final planoId = resolverPlanoDocId(a, ctx);

      debugPrint(

        '[GestaoComercial] assinatura plan_id=${a.planId} '

        'plan_name=${a.planName} status=${a.status} '

        'planoResolvido=$planoId ehGestao=${assinaturaEhGestaoComercial(a, ctx)}',

      );

    }

  }

  static bool assinaturaBloqueadaPeloAdmin(ClienteAssinaturaModel assinatura) {
    return assinatura.status == 'suspenso';
  }

  static ClienteAssinaturaModel? assinaturaBloqueioAdmin(
    List<ClienteAssinaturaModel> assinaturas,
    AssinaturaGestaoComercialContexto ctx,
  ) {
    for (final assinatura in filtrarAssinaturasGestao(assinaturas, ctx)) {
      if (assinaturaBloqueadaPeloAdmin(assinatura)) return assinatura;
    }
    return null;
  }

  static ClienteAssinaturaModel? assinaturaBloqueioInadimplencia(
    List<ClienteAssinaturaModel> assinaturas,
    AssinaturaGestaoComercialContexto ctx,
  ) {
    for (final assinatura in filtrarAssinaturasGestao(assinaturas, ctx)) {
      if (assinatura.deveEstarBloqueado) return assinatura;
    }
    return null;
  }

  static bool lojistaTemAcessoGestaoComercial(
    List<ClienteAssinaturaModel> assinaturas,
    AssinaturaGestaoComercialContexto ctx,
  ) {
    return filtrarAssinaturasGestao(assinaturas, ctx)
        .any(assinaturaTemAcessoGestao);
  }

  // ─── Módulo Emissão de NF-e (código estável + nome legado) ───

  /// Detecta se texto/código/nome representa o módulo de emissão fiscal.
  ///
  /// Aceita o código canônico [ModuloCodigos.emissaoNfe] e nomes como
  /// "Emissão de NF-e" gravados em `modulos_planos.modulos`.
  static bool textoIndicaEmissaoNfe(String? raw) {
    if (raw == null || raw.trim().isEmpty) return false;

    final codigo = ModuloCodigos.emissaoNfe;
    final normalizado = _normalizar(raw.trim());
    if (normalizado == codigo || normalizado.contains(codigo)) return true;

    // "emissao_de_nf_e", "emissao_nfe", "nf_e", etc.
    final temEmissao =
        normalizado.contains('emissao') || normalizado.contains('emitir');
    final temNfe = normalizado.contains('nfe') ||
        normalizado.contains('nf_e') ||
        normalizado.contains('nfc_e') ||
        normalizado.contains('nfs_e');
    if (temEmissao && temNfe) return true;

    final lower = raw.toLowerCase();
    if ((lower.contains('nf-e') ||
            lower.contains('nfe') ||
            lower.contains('nfc-e') ||
            lower.contains('nfs-e')) &&
        (lower.contains('emissão') ||
            lower.contains('emissao') ||
            lower.contains('nota fiscal'))) {
      return true;
    }

    return false;
  }

  static bool _moduloConfigEhEmissaoNfe(ModuloConfigModel? mod) {
    if (mod == null) return false;
    return textoIndicaEmissaoNfe(mod.codigo) ||
        textoIndicaEmissaoNfe(mod.nome);
  }

  static bool _moduloReferenciaEhEmissaoNfe(
    String? ref,
    AssinaturaGestaoComercialContexto ctx,
  ) {
    if (ref == null || ref.trim().isEmpty) return false;
    final chave = ref.trim();
    if (textoIndicaEmissaoNfe(chave)) return true;
    if (_moduloConfigEhEmissaoNfe(ctx.modulosPorNome[chave])) return true;
    if (_moduloConfigEhEmissaoNfe(ctx.modulosPorId[chave])) return true;

    // Catálogo: se a referência é o nome e o código do módulo é emissao_nfe
    final porNome = ctx.modulosPorNome[chave];
    if (porNome != null &&
        _normalizar(porNome.codigo) == ModuloCodigos.emissaoNfe) {
      return true;
    }
    return false;
  }

  /// Plano (doc `modulos_planos`) inclui o módulo Emissão de NF-e.
  static bool planoDocTemEmissaoNfe(
    Map<String, dynamic> data, {
    required AssinaturaGestaoComercialContexto ctx,
  }) {
    final mv = data['modulo_vinculado']?.toString() ?? '';
    if (_moduloReferenciaEhEmissaoNfe(mv, ctx)) return true;

    final modulos = data['modulos'];
    if (modulos is List) {
      for (final item in modulos) {
        if (_moduloReferenciaEhEmissaoNfe(item.toString(), ctx)) return true;
      }
    }
    return false;
  }

  /// Assinatura ativa com acesso GC e módulo NF-e no plano (ou extras).
  static bool assinaturaTemEmissaoNfe(
    ClienteAssinaturaModel assinatura,
    AssinaturaGestaoComercialContexto ctx,
  ) {
    if (!assinaturaTemAcessoGestao(assinatura)) return false;

    for (final mod in assinatura.modulosExtras) {
      if (_moduloReferenciaEhEmissaoNfe(mod, ctx)) return true;
    }

    final planoDocId = resolverPlanoDocId(assinatura, ctx);
    if (planoDocId == null) return false;
    final data = ctx.planosPorId[planoDocId];
    if (data == null) return false;
    return planoDocTemEmissaoNfe(data, ctx: ctx);
  }

  static bool lojistaTemModuloEmissaoNfe(
    List<ClienteAssinaturaModel> assinaturas,
    AssinaturaGestaoComercialContexto ctx,
  ) {
    return filtrarAssinaturasGestao(assinaturas, ctx)
        .any((a) => assinaturaTemEmissaoNfe(a, ctx));
  }

  /// Módulos do plano resolvido da assinatura (nomes/códigos como no Firestore).
  static List<String> modulosDoPlanoDaAssinatura(
    ClienteAssinaturaModel assinatura,
    AssinaturaGestaoComercialContexto ctx,
  ) {
    final planoDocId = resolverPlanoDocId(assinatura, ctx);
    if (planoDocId == null) return List<String>.from(assinatura.modulosExtras);
    final data = ctx.planosPorId[planoDocId];
    if (data == null) return List<String>.from(assinatura.modulosExtras);
    final raw = data['modulos'];
    final lista = raw is List
        ? raw.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList()
        : <String>[];
    if (assinatura.modulosExtras.isEmpty) return lista;
    final set = {...lista, ...assinatura.modulosExtras};
    return set.toList();
  }
}


/**
 * ⚠️ DEV ONLY — Limpeza total do marketplace Firestore + Auth.
 * Preserva apenas master@teste.com (e config de sistema: gateways, fretes, planos).
 */

const BATCH = 400;

/** Coleções apagadas por completo (todos os documentos). */
const COLECOES_RAIZ = [
  'pedidos',
  'encomendas',
  'produtos',
  'lojas_public',
  'cupons',
  'avaliacoes',
  'avaliacoes_produto',
  'saques_solicitacoes',
  'estornos',
  'receitas_app',
  'despesas_app',
  'notificacoes_campanhas',
  'users_cpf_index',
  'cadastro_telefone_verificado_tickets',
  'comtele_cadastro_rate_ip',
  'comtele_cadastro_rate_phone',
  'marketing_leads_lojistas',
  'marketing_leads_entregadores',
  'support_tickets',
  'support_ratings',
  'suporte',
  'candidaturas',
  'audit_logs',
  'audit_exclusoes_clientes',
  'password_reset_tokens',
  'password_reset_rate_email',
  'password_reset_rate_ip',
  'password_recovery_sessions',
  // Conteúdo operacional / marketing / utilidades (antes preservado)
  'banners',
  'comunicados',
  'servicos_destaque',
  'telefones_premium',
  'eventos',
  'vagas',
  'achados',
  'centro_ops_agenda',
];

/** Mantidas (config infra — sem dados de negócio). */
const COLECOES_PRESERVADAS = [
  'gateways_pagamento',
  'planos_taxas',
  'tabela_fretes',
  'configuracoes',
  'categorias',
  'sugestoes_categorias',
  'cidades',
  'cidades_atendidas',
  'conteudo_legal',
];

async function deleteQueryLoop(queryRef, label, dryRun, onLog) {
  const fs = queryRef.firestore;
  let total = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snap = await queryRef.limit(BATCH).get();
    if (snap.empty) break;
    if (dryRun) {
      total += snap.size;
      onLog?.(`[dry-run] ${label}: +${snap.size} (parcial ${total})`);
      break;
    }
    const batch = fs.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    total += snap.size;
    onLog?.(`${label}: apagados ${snap.size} (total ${total})`);
  }
  return total;
}

async function deleteSubcollection(db, parentRef, subName, dryRun, onLog) {
  const label = `${parentRef.path}/${subName}`;
  return deleteQueryLoop(parentRef.collection(subName), label, dryRun, onLog);
}

async function deletePedidosOuEncomendas(db, collectionName, dryRun, onLog) {
  let total = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snap = await db.collection(collectionName).limit(50).get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      await deleteSubcollection(db, doc.ref, 'mensagens', dryRun, onLog);
      if (!dryRun) await doc.ref.delete();
      total += 1;
    }
    onLog?.(`${collectionName}: ${total} doc(s) processado(s)`);
    if (dryRun) break;
  }
  return total;
}

async function deleteMarketingLeads(db, collectionName, dryRun, onLog) {
  let total = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snap = await db.collection(collectionName).limit(50).get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      await deleteSubcollection(db, doc.ref, 'historico', dryRun, onLog);
      if (!dryRun) await doc.ref.delete();
      total += 1;
    }
    if (dryRun) break;
  }
  return total;
}

async function deleteSupportTickets(db, dryRun, onLog) {
  let total = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snap = await db.collection('support_tickets').limit(50).get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      await deleteSubcollection(db, doc.ref, 'mensagens', dryRun, onLog);
      if (!dryRun) await doc.ref.delete();
      total += 1;
    }
    if (dryRun) break;
  }
  return total;
}

async function deleteSuporteLegacy(db, dryRun, onLog) {
  let total = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snap = await db.collection('suporte').limit(50).get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      await deleteSubcollection(db, doc.ref, 'mensagens', dryRun, onLog);
      if (!dryRun) await doc.ref.delete();
      total += 1;
    }
    if (dryRun) break;
  }
  return total;
}

async function deleteNotificacoesUsuario(db, dryRun, onLog) {
  let total = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snap = await db.collection('notificacoes_usuario').limit(50).get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      await deleteSubcollection(db, doc.ref, 'items', dryRun, onLog);
      if (!dryRun) await doc.ref.delete();
      total += 1;
    }
    if (dryRun) break;
  }
  return total;
}

async function deleteFiscalAll(db, dryRun, onLog) {
  const rootSnap = await db.collection('fiscal').get();
  if (dryRun) {
    onLog?.(`[dry-run] fiscal: ${rootSnap.size} entregador(es)`);
    return rootSnap.size;
  }
  for (const root of rootSnap.docs) {
    const anos = await root.ref.collection('anos').get();
    for (const ano of anos.docs) {
      const meses = await ano.ref.collection('meses').get();
      for (const mes of meses.docs) await mes.ref.delete();
      await ano.ref.delete();
    }
    await root.ref.delete();
  }
  onLog?.(`fiscal: removidos ${rootSnap.size}`);
  return rootSnap.size;
}

async function wipeUserSubcollections(db, uid, dryRun, onLog) {
  const base = `users/${uid}`;
  await deleteQueryLoop(
    db.collection(`${base}/enderecos`),
    `${base}/enderecos`,
    dryRun,
    onLog,
  );

  const veSnap = await db.collection(`${base}/veiculos`).get();
  for (const vdoc of veSnap.docs) {
    await deleteQueryLoop(
      vdoc.ref.collection('documentos'),
      `${base}/veiculos/${vdoc.id}/documentos`,
      dryRun,
      onLog,
    );
    if (!dryRun) await vdoc.ref.delete();
  }

  await deleteQueryLoop(
    db.collection(`${base}/documentos`),
    `${base}/documentos`,
    dryRun,
    onLog,
  );
  await deleteQueryLoop(
    db.collection(`${base}/chaves_pix`),
    `${base}/chaves_pix`,
    dryRun,
    onLog,
  );
  await deleteQueryLoop(
    db.collection(`${base}/tokens_fcm`),
    `${base}/tokens_fcm`,
    dryRun,
    onLog,
  );
  await deleteQueryLoop(
    db.collection(`${base}/bloqueios_auditoria`),
    `${base}/bloqueios_auditoria`,
    dryRun,
    onLog,
  );
}

async function contarColecao(db, name) {
  try {
    const agg = await db.collection(name).count().get();
    return agg.data().count;
  } catch (_) {
    const snap = await db.collection(name).limit(5000).get();
    return snap.size >= 5000 ? '5000+' : snap.size;
  }
}

async function contarLimpeza(db, auth) {
  const contagens = {};
  for (const c of COLECOES_RAIZ) {
    if (c === 'pedidos' || c === 'encomendas') continue;
    if (c === 'marketing_leads_lojistas' || c === 'marketing_leads_entregadores') continue;
    if (c === 'support_tickets' || c === 'suporte') continue;
    contagens[c] = await contarColecao(db, c);
  }
  contagens.pedidos = await contarColecao(db, 'pedidos');
  contagens.encomendas = await contarColecao(db, 'encomendas');
  contagens.fiscal = await contarColecao(db, 'fiscal');
  contagens.notificacoes_usuario = await contarColecao(db, 'notificacoes_usuario');

  const usersSnap = await db.collection('users').get();
  contagens.users_total = usersSnap.size;

  let authTotal = 0;
  let pageToken;
  do {
    const res = await auth.listUsers(1000, pageToken);
    authTotal += res.users.length;
    pageToken = res.pageToken;
  } while (pageToken);
  contagens.auth_total = authTotal;

  return {
    contagens,
    colecoesApagadas: COLECOES_RAIZ,
    colecoesPreservadas: COLECOES_PRESERVADAS,
  };
}

async function garantirMaster(auth, db, keepEmail, keepPassword) {
  let keepUid;
  try {
    const existing = await auth.getUserByEmail(keepEmail);
    keepUid = existing.uid;
    await auth.updateUser(keepUid, {
      password: keepPassword,
      emailVerified: true,
      displayName: 'Super Admin DiPertin',
    });
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      const created = await auth.createUser({
        email: keepEmail,
        password: keepPassword,
        emailVerified: true,
        displayName: 'Super Admin DiPertin',
      });
      keepUid = created.uid;
    } else {
      throw e;
    }
  }

  await db
    .collection('users')
    .doc(keepUid)
    .set(
      {
        email: keepEmail,
        nome: 'Super Admin',
        role: 'master',
        tipoUsuario: 'master',
        primeiro_acesso: false,
        ativo: true,
        saldo: 0,
      },
      { merge: true },
    );

  return keepUid;
}

async function apagarTodosAuthExceto(auth, keepUid, dryRun, onLog) {
  const uids = [];
  let pageToken;
  do {
    const res = await auth.listUsers(1000, pageToken);
    res.users.forEach((u) => {
      if (!keepUid || u.uid !== keepUid) uids.push(u.uid);
    });
    pageToken = res.pageToken;
  } while (pageToken);

  if (dryRun) {
    onLog?.(`[dry-run] Auth: apagaria ${uids.length} conta(s)`);
    return { ok: 0, falhas: 0, total: uids.length };
  }

  let ok = 0;
  let falhas = 0;
  for (const uid of uids) {
    try {
      await auth.deleteUser(uid);
      ok += 1;
    } catch (_) {
      falhas += 1;
    }
  }
  onLog?.(`Auth: ${ok} removido(s), ${falhas} falha(s)`);
  return { ok, falhas, total: uids.length };
}

async function apagarUsersFirestoreExceto(db, keepUid, dryRun, onLog) {
  const snap = await db.collection('users').get();
  const toRemove = keepUid
    ? snap.docs.filter((d) => d.id !== keepUid)
    : [...snap.docs];
  if (dryRun) {
    onLog?.(`[dry-run] users: apagaria ${toRemove.length} doc(s)`);
    return toRemove.length;
  }

  for (const doc of toRemove) {
    await wipeUserSubcollections(db, doc.id, false, onLog);
    await doc.ref.delete();
    onLog?.(`users/${doc.id} removido`);
  }
  return toRemove.length;
}

/**
 * Limpeza total: marketplace + usuários, mantém só master@teste.com.
 */
async function executarLimpezaTotal({
  auth,
  db,
  keepEmail,
  keepPassword,
  dryRun = false,
  onLog,
  onProgress,
}) {
  const log = (msg) => onLog?.(msg);
  const progress = (step, detail, status = 'running', extra = {}) =>
    onProgress?.({ step, detail, status, ts: Date.now(), ...extra });

  progress('inicio', dryRun ? 'Simulação (dry-run)' : 'Execução real', 'running');

  const resultado = {
    dryRun,
    keepEmail,
    etapas: {},
  };

  progress('pedidos', 'Apagando pedidos e mensagens…', 'running');
  resultado.etapas.pedidos = await deletePedidosOuEncomendas(
    db,
    'pedidos',
    dryRun,
    log,
  );
  progress('pedidos', `Pedidos: ${resultado.etapas.pedidos} processado(s)`, 'done', {
    count: resultado.etapas.pedidos,
  });

  progress('encomendas', 'Apagando encomendas…', 'running');
  resultado.etapas.encomendas = await deletePedidosOuEncomendas(
    db,
    'encomendas',
    dryRun,
    log,
  );
  progress('encomendas', `Encomendas: ${resultado.etapas.encomendas} processada(s)`, 'done', {
    count: resultado.etapas.encomendas,
  });

  progress('marketing', 'Apagando leads de marketing…', 'running');
  resultado.etapas.marketing_leads_lojistas = await deleteMarketingLeads(
    db,
    'marketing_leads_lojistas',
    dryRun,
    log,
  );
  resultado.etapas.marketing_leads_entregadores = await deleteMarketingLeads(
    db,
    'marketing_leads_entregadores',
    dryRun,
    log,
  );
  progress('marketing', 'Leads de marketing removidos', 'done');

  progress('suporte', 'Apagando tickets de suporte…', 'running');
  resultado.etapas.support_tickets = await deleteSupportTickets(db, dryRun, log);
  resultado.etapas.suporte = await deleteSuporteLegacy(db, dryRun, log);
  progress('suporte', 'Suporte removido', 'done');

  progress('notificacoes', 'Apagando notificações in-app…', 'running');
  resultado.etapas.notificacoes_usuario = await deleteNotificacoesUsuario(
    db,
    dryRun,
    log,
  );
  progress('notificacoes', 'Notificações removidas', 'done');

  progress('fiscal', 'Apagando dados fiscais de entregadores…', 'running');
  resultado.etapas.fiscal = await deleteFiscalAll(db, dryRun, log);
  progress('fiscal', `Fiscal: ${resultado.etapas.fiscal} removido(s)`, 'done', {
    count: resultado.etapas.fiscal,
  });

  const simples = COLECOES_RAIZ.filter(
    (c) =>
      ![
        'pedidos',
        'encomendas',
        'marketing_leads_lojistas',
        'marketing_leads_entregadores',
        'support_tickets',
        'suporte',
      ].includes(c),
  );

  progress('colecoes', 'Apagando coleções de marketplace…', 'running');
  for (const nome of simples) {
    progress(`col_${nome}`, `Apagando ${nome}…`, 'running');
    try {
      const n = await deleteQueryLoop(
        db.collection(nome),
        nome,
        dryRun,
        log,
      );
      resultado.etapas[nome] = n;
      progress(`col_${nome}`, `${nome}: ${n} doc(s)`, 'done', { count: n });
    } catch (e) {
      resultado.etapas[nome] = { erro: e.message };
      log(`Aviso ${nome}: ${e.message}`);
      progress(`col_${nome}`, `Erro em ${nome}: ${e.message}`, 'error');
    }
  }
  progress('colecoes', 'Coleções marketplace apagadas', 'done');

  progress('users', 'Apagando usuários (Firestore)…', 'running');
  let keepUidExistente = null;
  if (!dryRun) {
    try {
      keepUidExistente = (await auth.getUserByEmail(keepEmail)).uid;
    } catch (e) {
      if (e.code !== 'auth/user-not-found') throw e;
    }
  } else {
    const snapUsers = await db.collection('users').get();
    const masterDoc = snapUsers.docs.find(
      (d) =>
        String(d.data()?.email || '')
          .trim()
          .toLowerCase() === keepEmail,
    );
    keepUidExistente = masterDoc?.id || null;
  }

  resultado.etapas.users_removidos = await apagarUsersFirestoreExceto(
    db,
    keepUidExistente,
    dryRun,
    log,
  );
  progress('users', `Users: ${resultado.etapas.users_removidos} removido(s)`, 'done', {
    count: resultado.etapas.users_removidos,
  });

  if (!dryRun) {
    progress('master', 'Garantindo master@teste.com…', 'running');
    resultado.keepUid = await garantirMaster(auth, db, keepEmail, keepPassword);
    progress('master', 'Master configurado', 'done');

    progress('auth', 'Apagando contas Auth…', 'running');
    resultado.etapas.auth = await apagarTodosAuthExceto(
      auth,
      resultado.keepUid,
      false,
      log,
    );
    progress(
      'auth',
      `Auth: ${resultado.etapas.auth.ok} removido(s)`,
      'done',
      { count: resultado.etapas.auth.ok },
    );
  } else {
    const authResult = await apagarTodosAuthExceto(auth, keepUidExistente, true, log);
    resultado.etapas.auth = authResult;
  }

  progress('concluido', dryRun ? 'Simulação concluída' : 'Limpeza total concluída', 'done');
  progress('inicio', 'OK', 'done');
  resultado.colecoesPreservadas = COLECOES_PRESERVADAS;
  log(dryRun ? '=== DRY-RUN CONCLUÍDO ===' : '=== LIMPEZA TOTAL CONCLUÍDA ===');
  return resultado;
}

const ETAPAS_UI = [
  { id: 'inicio', label: 'Início' },
  { id: 'pedidos', label: 'Pedidos (+ mensagens)' },
  { id: 'encomendas', label: 'Encomendas (+ mensagens)' },
  { id: 'marketing', label: 'Leads marketing' },
  { id: 'suporte', label: 'Tickets suporte' },
  { id: 'notificacoes', label: 'Notificações in-app' },
  { id: 'fiscal', label: 'Dados fiscais' },
  { id: 'colecoes', label: 'Coleções marketplace' },
  { id: 'users', label: 'Usuários Firestore' },
  { id: 'master', label: 'Garantir master@teste.com' },
  { id: 'auth', label: 'Contas Firebase Auth' },
  { id: 'concluido', label: 'Concluído' },
];

module.exports = {
  COLECOES_RAIZ,
  COLECOES_PRESERVADAS,
  ETAPAS_UI,
  contarLimpeza,
  executarLimpezaTotal,
  garantirMaster,
  apagarTodosAuthExceto,
  apagarUsersFirestoreExceto,
};

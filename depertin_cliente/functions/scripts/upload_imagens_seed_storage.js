/**
 * Faz upload das imagens Unsplash para o Firebase Storage e atualiza
 * os documentos no Firestore.
 *
 * Uso:
 *   cd depertin_cliente/functions
 *   node scripts/upload_imagens_seed_storage.js
 */

const admin = require('firebase-admin');
const https = require('https');
const path = require('path');

if (!admin.apps.length) {
  admin.initializeApp({ projectId: 'depertin-f940f' });
}

const db = admin.firestore();
const bucket = admin.storage().bucket('depertin-f940f.firebasestorage.app');

const LOJAS = [
  { uid: 'seed_toledo_loja_1', nome: 'Empório do Pão', url: 'https://images.unsplash.com/photo-1549931319-a545753466bf?w=400', storagePath: 'seed/toledo/loja_emporio_pao.jpg' },
  { uid: 'seed_toledo_loja_2', nome: 'Açougue do Seu Zé', url: 'https://images.unsplash.com/photo-1559847844-5315695dadae?w=400', storagePath: 'seed/toledo/loja_acougue.jpg' },
  { uid: 'seed_toledo_loja_3', nome: 'Mercearia Oliveira', url: 'https://images.unsplash.com/photo-1558618666-fcd25c85f82e?w=400', storagePath: 'seed/toledo/loja_mercearia.jpg' },
  { uid: 'seed_toledo_loja_4', nome: 'Sushi Mania', url: 'https://images.unsplash.com/photo-1579871494447-9811cf80d66c?w=400', storagePath: 'seed/toledo/loja_sushi.jpg' },
  { uid: 'seed_toledo_loja_5', nome: 'Pizzaria Bella Napoli', url: 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=400', storagePath: 'seed/toledo/loja_pizzaria.jpg' },
  { uid: 'seed_toledo_loja_6', nome: 'Hortifruti Primavera', url: 'https://images.unsplash.com/photo-1590779033100-9f20a700f3d5?w=400', storagePath: 'seed/toledo/loja_hortifruti.jpg' },
  { uid: 'seed_toledo_loja_7', nome: 'Casa do Açaí', url: 'https://images.unsplash.com/photo-1599950755346-a3a58f1ad605?w=400', storagePath: 'seed/toledo/loja_acai.jpg' },
  { uid: 'seed_toledo_loja_8', nome: 'Lanchonete do Centro', url: 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=400', storagePath: 'seed/toledo/loja_lanches.jpg' },
  { uid: 'seed_toledo_loja_9', nome: 'Restaurante Sabor Caseiro', url: 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=400', storagePath: 'seed/toledo/loja_restaurante.jpg' },
  { uid: 'seed_toledo_loja_10', nome: 'Café & Prosa', url: 'https://images.unsplash.com/photo-1554118811-1e0d58224f24?w=400', storagePath: 'seed/toledo/loja_cafe.jpg' },
];

function downloadImage(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => resolve(Buffer.concat(chunks)));
      res.on('error', reject);
    }).on('error', reject);
  });
}

async function uploadBuffer(buffer, storagePath, contentType) {
  const file = bucket.file(storagePath);
  await file.save(buffer, {
    metadata: { contentType, cacheControl: 'public, max-age=31536000' },
  });
  await file.makePublic();
  return `https://firebasestorage.googleapis.com/v0/b/depertin-f940f.firebasestorage.app/o/${encodeURIComponent(storagePath)}?alt=media`;
}

async function atualizarFirestore(lojaUid, storageUrl) {
  // Atualiza users
  await db.collection('users').doc(lojaUid).update({
    foto_perfil: storageUrl,
    imagem: storageUrl,
  }).catch(() => {});

  // Atualiza lojas_public
  await db.collection('lojas_public').doc(lojaUid).update({
    foto_perfil: storageUrl,
    imagem: storageUrl,
  }).catch(() => {});

  // Atualiza todos os produtos desta loja
  const prods = await db.collection('produtos').where('lojista_id', '==', lojaUid).get();
  const batch = db.batch();
  let count = 0;
  for (const doc of prods.docs) {
    batch.update(doc.ref, {
      imagens: [storageUrl],
    });
    count++;
  }
  if (count > 0) await batch.commit();
  return prods.docs.length;
}

async function main() {
  console.log('Iniciando upload de imagens para Firebase Storage...\n');

  for (let i = 0; i < LOJAS.length; i++) {
    const loja = LOJAS[i];
    process.stdout.write(`[${i + 1}/${LOJAS.length}] ${loja.nome}... `);

    try {
      // Download
      const buffer = await downloadImage(loja.url);
      process.stdout.write('download ok, ');

      // Upload
      const storageUrl = await uploadBuffer(buffer, loja.storagePath, 'image/jpeg');
      process.stdout.write('upload ok, ');

      // Atualiza Firestore
      const qtdeProdutos = await atualizarFirestore(loja.uid, storageUrl);
      console.log(`Firestore ok (1 loja + ${qtdeProdutos} produtos)`);
    } catch (err) {
      console.error(`FALHOU: ${err.message}`);
    }
  }

  console.log('\n✅ Upload concluído! Todas as imagens agora são servidas do Firebase Storage.');
  process.exit(0);
}

main().catch((err) => {
  console.error('Erro fatal:', err);
  process.exit(1);
});

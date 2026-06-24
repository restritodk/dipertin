/**
 * Reenvia as imagens das lojas fictícias para um caminho com permissão
 * pública de leitura nas regras do Storage: banners_vitrine/seed_toledo/
 *
 * As imagens ficam sob banners_vitrine/ que já tem allow read: if true.
 */
const admin = require('firebase-admin');
const https = require('https');

const BUCKET_NAME = 'depertin-f940f.firebasestorage.app';
const STORAGE_PREFIX = 'banners_vitrine/seed_toledo/';

const LOJAS = [
  {
    uid: 'seed_toledo_loja_1',
    nome: 'Empório do Pão & Cia',
    url: 'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=400',
    storageName: 'loja_emporio_pao.jpg',
    produtos: [
      'https://images.unsplash.com/photo-1549931319-a545753458ee?w=400',
      'https://images.unsplash.com/photo-1509365465985-25d11c17e812?w=400',
      'https://images.unsplash.com/photo-1608198093002-ad4e00548442?w=400',
      'https://images.unsplash.com/photo-1507003932026-0b53a5b6a2f2?w=400',
      'https://images.unsplash.com/photo-1621857094158-1fd0e250c9f6?w=400',
      'https://images.unsplash.com/photo-1558637845-2f0f9a0e7c1a?w=400',
      'https://images.unsplash.com/photo-1612206986630-35168a3e12a0?w=400',
      'https://images.unsplash.com/photo-1509551388413-ea45c9c12d73?w=400',
      'https://images.unsplash.com/photo-1618885472177-1e1a2b8e6b8d?w=400',
      'https://images.unsplash.com/photo-1588195538326-c5b1e9f80a1b?w=400',
    ],
  },
  {
    uid: 'seed_toledo_loja_2',
    nome: 'Açougue do Toledo',
    url: 'https://images.unsplash.com/photo-1607623814075-e51df1bdc82f?w=400',
    storageName: 'loja_acougue.jpg',
    produtos: [
      'https://images.unsplash.com/photo-1529692236671-f1f6cf9683ba?w=400',
      'https://images.unsplash.com/photo-1603048297172-c92544798bdb?w=400',
      'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400',
      'https://images.unsplash.com/photo-1544025162-d76694265947?w=400',
      'https://images.unsplash.com/photo-1432139555190-58524dae6a55?w=400',
      'https://images.unsplash.com/photo-1559847844-5315695dadae?w=400',
      'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400',
      'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=400',
      'https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=400',
      'https://images.unsplash.com/photo-1565958011703-44f9829ba187?w=400',
    ],
  },
  {
    uid: 'seed_toledo_loja_3',
    nome: 'Mercearia São João',
    url: 'https://images.unsplash.com/photo-1542838132-92c53300491e?w=400',
    storageName: 'loja_mercearia.jpg',
    produtos: [
      'https://images.unsplash.com/photo-1518976124510-ce8d2c4c6f57?w=400',
      'https://images.unsplash.com/photo-1590779033100-9f52a38f3f0b?w=400',
      'https://images.unsplash.com/photo-1579113800032-c38bd7635818?w=400',
      'https://images.unsplash.com/photo-1557844352-761f2565b576?w=400',
      'https://images.unsplash.com/photo-1571805617045-fbc2e7a6d96f?w=400',
      'https://images.unsplash.com/photo-1574226516831-e1dff420e562?w=400',
      'https://images.unsplash.com/photo-1584269600469-67fa60f9b1b2?w=400',
      'https://images.unsplash.com/photo-1615484477678-3d8d2f3a47b5?w=400',
      'https://images.unsplash.com/photo-1619566636858-adf3ef46400b?w=400',
      'https://images.unsplash.com/photo-1591688511396-e38d10d0fcc3?w=400',
    ],
  },
  {
    uid: 'seed_toledo_loja_4',
    nome: 'Sushi Toledo',
    url: 'https://images.unsplash.com/photo-1579027989536-b7b1f875659b?w=400',
    storageName: 'loja_sushi.jpg',
    produtos: [
      'https://images.unsplash.com/photo-1553621042-f6e147245754?w=400',
      'https://images.unsplash.com/photo-1579584425555-c3ce17fd4351?w=400',
      'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400',
      'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=400',
      'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=400',
      'https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=400',
      'https://images.unsplash.com/photo-1565958011703-44f9829ba187?w=400',
      'https://images.unsplash.com/photo-1482049016688-2d3e1b311543?w=400',
      'https://images.unsplash.com/photo-1484723091739-30a097e8f929?w=400',
      'https://images.unsplash.com/photo-1476224203421-9ac39bcb3327?w=400',
    ],
  },
  {
    uid: 'seed_toledo_loja_5',
    nome: 'Pizzaria do Chef',
    url: 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=400',
    storageName: 'loja_pizzaria.jpg',
    produtos: [
      'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=400',
      'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=400',
      'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400',
      'https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=400',
      'https://images.unsplash.com/photo-1565958011703-44f9829ba187?w=400',
      'https://images.unsplash.com/photo-1482049016688-2d3e1b311543?w=400',
      'https://images.unsplash.com/photo-1484723091739-30a097e8f929?w=400',
      'https://images.unsplash.com/photo-1476224203421-9ac39bcb3327?w=400',
      'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400',
      'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400',
    ],
  },
  {
    uid: 'seed_toledo_loja_6',
    nome: 'Hortifruti Toledo Verde',
    url: 'https://images.unsplash.com/photo-1542838132-92c53300491e?w=400',
    storageName: 'loja_hortifruti.jpg',
    produtos: [
      'https://images.unsplash.com/photo-1518976124510-ce8d2c4c6f57?w=400',
      'https://images.unsplash.com/photo-1590779033100-9f52a38f3f0b?w=400',
      'https://images.unsplash.com/photo-1579113800032-c38bd7635818?w=400',
      'https://images.unsplash.com/photo-1557844352-761f2565b576?w=400',
      'https://images.unsplash.com/photo-1571805617045-fbc2e7a6d96f?w=400',
      'https://images.unsplash.com/photo-1574226516831-e1dff420e562?w=400',
      'https://images.unsplash.com/photo-1584269600469-67fa60f9b1b2?w=400',
      'https://images.unsplash.com/photo-1615484477678-3d8d2f3a47b5?w=400',
      'https://images.unsplash.com/photo-1619566636858-adf3ef46400b?w=400',
      'https://images.unsplash.com/photo-1591688511396-e38d10d0fcc3?w=400',
    ],
  },
  {
    uid: 'seed_toledo_loja_7',
    nome: 'Açaí & Saúde',
    url: 'https://images.unsplash.com/photo-1590301157890-4810ed352733?w=400',
    storageName: 'loja_acai.jpg',
    produtos: [
      'https://images.unsplash.com/photo-1590301157890-4810ed352733?w=400',
      'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400',
      'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=400',
      'https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=400',
      'https://images.unsplash.com/photo-1565958011703-44f9829ba187?w=400',
      'https://images.unsplash.com/photo-1482049016688-2d3e1b311543?w=400',
      'https://images.unsplash.com/photo-1484723091739-30a097e8f929?w=400',
      'https://images.unsplash.com/photo-1476224203421-9ac39bcb3327?w=400',
      'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400',
      'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400',
    ],
  },
  {
    uid: 'seed_toledo_loja_8',
    nome: 'Lanchonete do Zezé',
    url: 'https://images.unsplash.com/photo-1550547660-d9450f859349?w=400',
    storageName: 'loja_lanches.jpg',
    produtos: [
      'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=400',
      'https://images.unsplash.com/photo-1550547660-d9450f859349?w=400',
      'https://images.unsplash.com/photo-1594212699903-ec8a3eca50f5?w=400',
      'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=400',
      'https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=400',
      'https://images.unsplash.com/photo-1565958011703-44f9829ba187?w=400',
      'https://images.unsplash.com/photo-1482049016688-2d3e1b311543?w=400',
      'https://images.unsplash.com/photo-1484723091739-30a097e8f929?w=400',
      'https://images.unsplash.com/photo-1476224203421-9ac39bcb3327?w=400',
      'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400',
    ],
  },
  {
    uid: 'seed_toledo_loja_9',
    nome: 'Restaurante La Mesa',
    url: 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=400',
    storageName: 'loja_restaurante.jpg',
    produtos: [
      'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400',
      'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=400',
      'https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=400',
      'https://images.unsplash.com/photo-1565958011703-44f9829ba187?w=400',
      'https://images.unsplash.com/photo-1482049016688-2d3e1b311543?w=400',
      'https://images.unsplash.com/photo-1484723091739-30a097e8f929?w=400',
      'https://images.unsplash.com/photo-1476224203421-9ac39bcb3327?w=400',
      'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400',
      'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=400',
      'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=400',
    ],
  },
  {
    uid: 'seed_toledo_loja_10',
    nome: 'Café Colonial Toledo',
    url: 'https://images.unsplash.com/photo-1559305616-3f99cd43e353?w=400',
    storageName: 'loja_cafe.jpg',
    produtos: [
      'https://images.unsplash.com/photo-1509042239860-f550ce710b93?w=400',
      'https://images.unsplash.com/photo-1559305616-3f99cd43e353?w=400',
      'https://images.unsplash.com/photo-1498804103079-a6351b050096?w=400',
      'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=400',
      'https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=400',
      'https://images.unsplash.com/photo-1565958011703-44f9829ba187?w=400',
      'https://images.unsplash.com/photo-1482049016688-2d3e1b311543?w=400',
      'https://images.unsplash.com/photo-1484723091739-30a097e8f929?w=400',
      'https://images.unsplash.com/photo-1476224203421-9ac39bcb3327?w=400',
      'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400',
    ],
  },
];

function downloadImage(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' } }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        https.get(res.headers.location, { headers: { 'User-Agent': 'Mozilla/5.0' } }, (res2) => {
          const chunks = [];
          res2.on('data', c => chunks.push(c));
          res2.on('end', () => resolve(Buffer.concat(chunks)));
          res2.on('error', reject);
        });
        return;
      }
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks)));
      res.on('error', reject);
    }).on('error', reject);
  });
}

async function uploadBuffer(buffer, storagePath) {
  const bucket = admin.storage().bucket(BUCKET_NAME);
  const file = bucket.file(STORAGE_PREFIX + storagePath);
  await file.save(buffer, { metadata: { contentType: 'image/jpeg' } });
  const publicUrl = `https://firebasestorage.googleapis.com/v0/b/${BUCKET_NAME}/o/${encodeURIComponent(STORAGE_PREFIX + storagePath)}?alt=media`;
  return publicUrl;
}

async function main() {
  if (!admin.apps.length) admin.initializeApp({ projectId: 'depertin-f940f' });
  const db = admin.firestore();

  for (let i = 0; i < LOJAS.length; i++) {
    const loja = LOJAS[i];
    console.log(`[${i + 1}/${LOJAS.length}] ${loja.nome}`);

    // 1. Baixar e enviar logo da loja
    try {
      const logoBuffer = await downloadImage(loja.url);
      const logoUrl = await uploadBuffer(logoBuffer, loja.storageName);
      console.log(`   Logo enviada: ${logoUrl}`);

      // Atualiza users e lojas_public
      await db.collection('users').doc(loja.uid).update({ foto_perfil: logoUrl });
      await db.collection('lojas_public').doc(loja.uid).update({ foto_perfil: logoUrl });
      console.log(`   Firestore users/lojas_public atualizado`);
    } catch (e) {
      console.error(`   ⚠️ Erro logo: ${e.message}`);
    }

    // 2. Baixar e enviar imagens dos produtos
    const prodSnap = await db.collection('produtos').where('lojista_id', '==', loja.uid).get();
    const produtos = prodSnap.docs;
    console.log(`   ${produtos.length} produtos para processar`);

    for (let p = 0; p < Math.min(produtos.length, loja.produtos.length); p++) {
      const prodDoc = produtos[p];
      const unsplashUrl = loja.produtos[p];
      const nomeArquivo = `${loja.storageName.replace('.jpg', '')}_prod_${p}.jpg`;

      try {
        const imgBuffer = await downloadImage(unsplashUrl);
        const imgUrl = await uploadBuffer(imgBuffer, nomeArquivo);
        await prodDoc.ref.update({ imagens: [imgUrl] });
        if ((p + 1) % 3 === 0) process.stdout.write('.');
      } catch (e) {
        console.error(`   ⚠️ Produto ${p}: ${e.message}`);
      }
    }
    console.log(`\n   ✅ ${Math.min(produtos.length, loja.produtos.length)} produtos atualizados`);
  }

  console.log('\n✅ Todas as imagens reenviadas para banners_vitrine/seed_toledo/!');
}

main().catch(console.error).then(() => process.exit(0));

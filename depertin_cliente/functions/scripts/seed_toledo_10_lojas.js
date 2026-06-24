/**
 * Seed: Cria 10 lojas em Toledo-PR, cada uma com 10 produtos + descrições.
 *
 * Pré-requisitos:
 *   1. `npm install` em functions/
 *   2. GOOGLE_APPLICATION_CREDENTIALS apontando para service account OU
 *      `gcloud auth application-default login`
 *
 * Uso:
 *   cd depertin_cliente/functions
 *   node scripts/seed_toledo_10_lojas.js
 */

const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp({ projectId: 'depertin-f940f' });
}

const db = admin.firestore();
const CIDADE = 'Toledo';
const CIDADE_LOWER = CIDADE.toLowerCase();

// ─── 10 lojas com dados temáticos ───────────────────────────────────────────
const diasDaSemana = ['segunda','terca','quarta','quinta','sexta','sabado','domingo'];
const horariosCompleto = {};
for (const d of diasDaSemana) {
  horariosCompleto[d] = { ativo: true, abre: '06:00', fecha: '23:00' };
}

// Serão substituídas pelas URLs do Storage após upload
const URLS_STORAGE = {};

const LOJAS = [
  {
    nome: 'Empório do Pão',
    descricao: 'Padaria artesanal com pães, bolos e salgados feitos diariamente com ingredientes selecionados.',
    categoria: 'Padaria & Confeitaria',
    foto: 'https://images.unsplash.com/photo-1549931319-a545753466bf?w=400',
    fotoStorage: 'seed/toledo/loja_emporio_pao.jpg',
    produtos: [
      { nome: 'Pão Francês Fresco', preco: 0.99, descricao: 'Pão francês assado na hora, crocante por fora e macio por dentro. Ideal para o café da manhã.' },
      { nome: 'Bolo de Cenoura com Cobertura', preco: 18.90, descricao: 'Bolo de cenoura fofinho com cobertura de chocolate belga. Serve até 8 pessoas.' },
      { nome: 'Sonho Recheado', preco: 6.50, descricao: 'Massa de sonho fritinha recheada com creme de baunilha e polvilhada com açúcar.' },
      { nome: 'Pão Integral Caseiro', preco: 12.90, descricao: 'Pão integral feito com farinha orgânica, aveia, linhaça e girassol. 500g.' },
      { nome: 'Croissant de Presunto e Queijo', preco: 8.90, descricao: 'Croissant folhado recheado com presunto e mussarela, perfeito para o lanche.' },
      { nome: 'Biscoitos Amanteigados', preco: 9.90, descricao: 'Biscoitos amanteigados sortidos (goiabada, coco, chocolate). Pote com 300g.' },
      { nome: 'Torta Holandesa', preco: 34.90, descricao: 'Torta holandesa com base de biscoito, creme suave e cobertura de chocolate. 20cm.' },
      { nome: 'Pão de Queijo Mineiro', preco: 15.90, descricao: 'Pão de queijo feito com queijo canastra e polvilho azedo. Pacote com 500g.' },
      { nome: 'Empada de Frango', preco: 7.50, descricao: 'Empada de frango com catupiry, massa podre e selo artesanal. Unidade.' },
      { nome: 'Baguete Recheada', preco: 22.90, descricao: 'Baguete crocante recheada com rosbife, rúcula, tomate seco e maionese temperada.' },
    ],
  },
  {
    nome: 'Açougue do Seu Zé',
    descricao: 'Carnes de primeira qualidade, cortes especiais e atendimento personalizado no bairro.',
    categoria: 'Açougue',
    foto: 'https://images.unsplash.com/photo-1559847844-5315695dadae?w=400',
    produtos: [
      { nome: 'Picanha Nobre kg', preco: 69.90, descricao: 'Picanha maturada por 21 dias, marmoreio perfeito. Corte especial para churrasco.' },
      { nome: 'Alcatra kg', preco: 39.90, descricao: 'Alcatra bovina limpa, sem nervos. Ideal para bifes, churrasco e ensopados.' },
      { nome: 'Coxa de Frango kg', preco: 14.90, descricao: 'Coxa de frango resfriada, limpa e sem pele. Ótima para assar ou fritar.' },
      { nome: 'Costela Bovina kg', preco: 28.90, descricao: 'Costela bovina com osso, cortada em tiras. Perfeita para churrasco lento.' },
      { nome: 'Linguiça Artesanal kg', preco: 22.90, descricao: 'Linguiça de porco artesanal temperada com ervas finas. Pacote 1kg.' },
      { nome: 'Maminha kg', preco: 44.90, descricao: 'Maminha bovina macia, ideal para churrasco e bifes grelhados. Corte nobre.' },
      { nome: 'Carne Moída Patinho kg', preco: 28.90, descricao: 'Carne moída na hora de patinho, sem excesso de gordura. Perfeita para hambúrgueres.' },
      { nome: 'Frango Inteiro kg', preco: 16.90, descricao: 'Frango inteiro resfriado, limpo e embalado. Ótimo para assar no forno.' },
      { nome: 'Contra-filé kg', preco: 49.90, descricao: 'Contra-filé bovino com gordura na medida certa. Sabor inconfundível.' },
      { nome: 'Costelinha de Porco kg', preco: 24.90, descricao: 'Costelinha suína temperada com molho barbecue. Ideal para churrasco.' },
    ],
  },
  {
    nome: 'Mercearia Oliveira',
    descricao: 'Mercearia completa com alimentos, bebidas, limpeza e hortifrúti. Preço justo e variedade.',
    categoria: 'Mercearia',
    foto: 'https://images.unsplash.com/photo-1558618666-fcd25c85f82e?w=400',
    produtos: [
      { nome: 'Arroz Tipo 1 5kg', preco: 24.90, descricao: 'Arroz branco tipo 1, grãos longos e soltinhos após o cozimento. Pacote 5kg.' },
      { nome: 'Feijão Carioca 1kg', preco: 7.90, descricao: 'Feijão carioca de primeira qualidade, selecionado e lavado. Pacote 1kg.' },
      { nome: 'Açúcar Cristal 5kg', preco: 18.90, descricao: 'Açúcar cristal fino, ideal para uso diário. Pacote 5kg.' },
      { nome: 'Óleo de Soja 900ml', preco: 6.90, descricao: 'Óleo de soja refinado, ideal para frituras e preparo de alimentos.' },
      { nome: 'Café Torrado Moído 500g', preco: 14.90, descricao: 'Café torrado e moído na hora, aroma intenso e sabor marcante. Pacote 500g.' },
      { nome: 'Leite UHT Integral 1L', preco: 4.90, descricao: 'Leite integral UHT caixinha, fonte de cálcio e vitaminas.' },
      { nome: 'Macarrão Espaguete 500g', preco: 4.50, descricao: 'Macarrão tipo espaguete, sêmola de trigo. Cozimento rápido.' },
      { nome: 'Molho de Tomate 340g', preco: 3.90, descricao: 'Molho de tomate temperado, pronto para uso. Sache 340g.' },
      { nome: 'Sal Refinado 1kg', preco: 2.90, descricao: 'Sal refinado iodado, pacote 1kg.' },
      { nome: 'Biscoito Cream Cracker 400g', preco: 5.90, descricao: 'Biscoito cream cracker, crocante e levemente salgado. Pacote 400g.' },
    ],
  },
  {
    nome: 'Sushi Mania',
    descricao: 'Comida japonesa artesanal com delivery rápido. Peixe fresco todos os dias.',
    categoria: 'Comida Japonesa',
    foto: 'https://images.unsplash.com/photo-1579871494447-9811cf80d66c?w=400',
    produtos: [
      { nome: 'Combinado 30 Peças', preco: 54.90, descricao: '30 peças variadas: 8 sushis salmão, 8 sushis atum, 6 hossomaki, 4 uramaki, 4 niguiri.' },
      { nome: 'Temaki Salmão', preco: 18.90, descricao: 'Temaki de salmão fresco com cream cheese e cebolinha. Alga crocante.' },
      { nome: 'Uramaki Filadélfia 8pç', preco: 24.90, descricao: 'Uramaki de salmão com cream cheese, envolto em gergelim. 8 unidades.' },
      { nome: 'Sashimi Salmão 15 fatias', preco: 32.90, descricao: 'Sashimi de salmão fresco cortado em fatias generosas. Acompanha shoyu.' },
      { nome: 'Hot Roll 10 peças', preco: 28.90, descricao: 'Hot roll empanado e frito, recheado com salmão e cream cheese. 10 unidades.' },
      { nome: 'Combinado Jumbo 50pç', preco: 89.90, descricao: 'Combinado especial 50 peças com sushis, sashimis, uramakis e temakis.' },
      { nome: 'Sunomono', preco: 12.90, descricao: 'Salada de pepino ao molho agridoce com gergelim e vinagre de arroz.' },
      { nome: 'Yakisoba de Frango', preco: 26.90, descricao: 'Macarrão oriental frito com frango, legumes e shoyu. Porção individual.' },
      { nome: 'Missoshiru', preco: 9.90, descricao: 'Sopa tradicional japonesa de missô com tofu, cebolinha e algas wakame.' },
      { nome: 'Guioza de Salmão 8un', preco: 22.90, descricao: 'Guioza de salmão grelhada, servida com molho teriyaki. 8 unidades.' },
    ],
  },
  {
    nome: 'Pizzaria Bella Napoli',
    descricao: 'Massas italianas finas e crocantes, ingredientes importados e forno à lenha.',
    categoria: 'Pizzaria',
    foto: 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=400',
    produtos: [
      { nome: 'Pizza Margherita Grande', preco: 39.90, descricao: 'Molho de tomate italiano, mussarela de búfala, manjericão fresco e azeite.' },
      { nome: 'Pizza Pepperoni Grande', preco: 44.90, descricao: 'Pepperoni importado, mussarela e orégano. Massa fina e crocante.' },
      { nome: 'Pizza Quatro Queijos Grande', preco: 47.90, descricao: 'Mussarela, parmesão, gorgonzola e catupiry. Cobertura generosa.' },
      { nome: 'Pizza Portuguesa Grande', preco: 45.90, descricao: 'Presunto, ovos, cebola, azeitona, pimentão e mussarela.' },
      { nome: 'Pizza Frango com Catupiry', preco: 43.90, descricao: 'Frango desfiado temperado com catupiry cremoso e milho verde.' },
      { nome: 'Pizza Calabresa Grande', preco: 42.90, descricao: 'Calabresa fatiada, cebola roxa, mussarela e azeitonas pretas.' },
      { nome: 'Pizza Doce Chocolate', preco: 49.90, descricao: 'Chocolate belga derretido, morangos frescos e granulado. Massa doce.' },
      { nome: 'Esfirra de Carne 5un', preco: 18.90, descricao: 'Esfirras abertas de carne temperada com tomate, cebola e hortelã. 5 unidades.' },
      { nome: 'Borda Recheada Catupiry', preco: 8.90, descricao: 'Adicional de borda recheada com catupiry cremoso para qualquer pizza grande.' },
      { nome: 'Refrigerante 2L', preco: 9.90, descricao: 'Refrigerante Coca-Cola 2L, gelada para acompanhar sua pizza.' },
    ],
  },
  {
    nome: 'Hortifruti Primavera',
    descricao: 'Frutas, verduras e legumes orgânicos fresquinhos direto do produtor rural.',
    categoria: 'Hortifrúti',
    foto: 'https://images.unsplash.com/photo-1590779033100-9f20a700f3d5?w=400',
    produtos: [
      { nome: 'Banana Prata Maço', preco: 5.90, descricao: 'Banana prata madura no ponto, doce e firme. Maço com aproximadamente 1kg.' },
      { nome: 'Maçã Gala kg', preco: 8.90, descricao: 'Maçã gala fresca e crocante, ótima para consumo in natura ou saladas.' },
      { nome: 'Alface Crespa Unidade', preco: 3.50, descricao: 'Alface crespa verde, folhas crocantes e frescas. Unidade.' },
      { nome: 'Tomate Italiano kg', preco: 7.90, descricao: 'Tomate italiano selecionado, firme e saboroso. Ideal para molhos e saladas.' },
      { nome: 'Cebola Roxa kg', preco: 5.50, descricao: 'Cebola roxa fresca, sabor levemente adocicado. Pacote 1kg.' },
      { nome: 'Laranja Pera kg', preco: 4.90, descricao: 'Laranja pera doce e suculenta, ótima para suco ou consumo in natura.' },
      { nome: 'Batata Inglesa kg', preco: 5.90, descricao: 'Batata inglesa lavada, selecionada. Ideal para fritas e purê.' },
      { nome: 'Cenoura kg', preco: 4.50, descricao: 'Cenoura fresca, crocante e doce. Pacote 1kg.' },
      { nome: 'Abacate Avocado Unidade', preco: 7.90, descricao: 'Abacate avocado no ponto, cremoso e nutritivo. Unidade grande.' },
      { nome: 'Morango Bandeja', preco: 12.90, descricao: 'Morango fresco e doce, bandeja com aproximadamente 300g.' },
    ],
  },
  {
    nome: 'Casa do Açaí',
    descricao: 'Açaí premium, sorvetes artesanais e sobremesas geladas. O melhor da região.',
    categoria: 'Sorveteria & Açaí',

    foto: 'https://images.unsplash.com/photo-1599950755346-a3a58f1ad605?w=400',
    produtos: [
      { nome: 'Açaí Médio 500ml', preco: 18.90, descricao: 'Açaí puro cremoso 500ml com granola, banana, leite condensado e paçoca.' },
      { nome: 'Açaí Grande 700ml', preco: 24.90, descricao: 'Açaí cremoso 700ml com 3 acompanhamentos: granola, banana, leite em pó, paçoca ou morango.' },
      { nome: 'Sorvete Casquinha', preco: 7.90, descricao: 'Casquinha crocante com sorvete artesanal. Sabores: chocolate, morango ou creme.' },
      { nome: 'Milk Shake Chocolate', preco: 16.90, descricao: 'Milk shake cremoso de chocolate batido com sorvete artesanal. Caneca 400ml.' },
      { nome: 'Taça de Sorvete Especial', preco: 22.90, descricao: 'Taça com 3 bolas de sorvete, caldas quentes, frutas e chantilly.' },
      { nome: 'Picolé Artesanal', preco: 8.50, descricao: 'Picolé artesanal de fruta ou chocolate. Sabores: limão, maracujá, coco, chocolate.' },
      { nome: 'Smoothie de Frutas', preco: 14.90, descricao: 'Smoothie natural de frutas batido com iogurte. Sabores: morango, manga ou açaí.' },
      { nome: 'Petit Gateau', preco: 19.90, descricao: 'Petit gateau de chocolate belga com sorvete de creme e calda de frutas vermelhas.' },
      { nome: 'Açaí Tigela 300ml', preco: 13.90, descricao: 'Açaí na tigela 300ml com granola artesanal e fios de mel.' },
      { nome: 'Sorvete 1L Pote', preco: 28.90, descricao: 'Sorvete artesanal pote 1 litro. Sabores: chocolate, creme, flocos, morango.' },
    ],
  },
  {
    nome: 'Lanchonete do Centro',
    descricao: 'Hambúrgueres artesanais, porções e lanches rápidos. Ambiente familiar desde 2010.',
    categoria: 'Lanches & Hamburgueria',

    foto: 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=400',
    produtos: [
      { nome: 'X-Burguer Completo', preco: 22.90, descricao: 'Hambúrguer 180g, queijo cheddar, alface, tomate, cebola roxa e molho especial.' },
      { nome: 'X-Salada', preco: 18.90, descricao: 'Hambúrguer 150g, queijo mussarela, alface, tomate e maionese caseira.' },
      { nome: 'X-Bacon', preco: 28.90, descricao: 'Hambúrguer 200g, bacon crocante, cheddar, alface, tomate e molho barbecue.' },
      { nome: 'Combo X-Tudo', preco: 34.90, descricao: 'Hambúrguer 250g, bacon, ovo, calabresa, queijo, alface, tomate + batata frita + refri.' },
      { nome: 'Batata Frita Grande', preco: 14.90, descricao: 'Batata frita sequinha e crocante com cheddar e bacon. Porção grande.' },
      { nome: 'Onion Rings', preco: 12.90, descricao: 'Anéis de cebola empanados e fritos, servidos com molho barbecue. 8 unidades.' },
      { nome: 'Hot Dog Especial', preco: 16.90, descricao: 'Pão artesanal, salsicha, purê, vinagrete, milho, ervilha e batata palha.' },
      { nome: 'Combo Kids', preco: 19.90, descricao: 'Hambúrguer 100g, queijo, batata frita pequena, suco e surpresa.' },
      { nome: 'Porção de Frango à Passarinho', preco: 24.90, descricao: 'Frango à passarinho temperado e frito na hora. Porção para 2 pessoas.' },
      { nome: 'Refrigerante Lata', preco: 5.90, descricao: 'Refrigerante lata 350ml. Coca, Guaraná, Fanta ou Sprite.' },
    ],
  },
  {
    nome: 'Restaurante Sabor Caseiro',
    descricao: 'Comida caseira feita com amor, marmitex e pratos executivos delivery.',
    categoria: 'Restaurante',

    foto: 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=400',
    produtos: [
      { nome: 'Prato Executivo Frango', preco: 18.90, descricao: 'Frango grelhado, arroz, feijão carioca, farofa, salada e batata frita.' },
      { nome: 'Marmitex Bife Acebolado', preco: 16.90, descricao: 'Bife acebolado, arroz, feijão tropeiro, couve refogada e ovo.' },
      { nome: 'PF Costela no Bafo', preco: 24.90, descricao: 'Costela bovina cozida lentamente, arroz, feijão, mandioca cremosa e vinagrete.' },
      { nome: 'Strogonoff de Frango', preco: 22.90, descricao: 'Strogonoff de frango ao molho cremoso, arroz branco e batata palha.' },
      { nome: 'Lasanha à Bolonhesa', preco: 26.90, descricao: 'Lasanha de carne moída com molho bolonhesa, queijo e molho branco. Porção individual.' },
      { nome: 'Salada Caesar', preco: 19.90, descricao: 'Salada Caesar com alface romana, croutons, parmesão e molho Caesar.' },
      { nome: 'Filé de Peixe Grelhado', preco: 27.90, descricao: 'Filé de tilápia grelhado, purê de batata, legumes refogados e arroz.' },
      { nome: 'Marmita Fitness', preco: 21.90, descricao: 'Frango grelhado, quinoa, brócolis, batata doce e salada de folhas.' },
      { nome: 'Macarrão Alho e Óleo', preco: 14.90, descricao: 'Macarrão ao alho e óleo com brócolis, tomate seco e parmesão ralado.' },
      { nome: 'Suco Natural 500ml', preco: 8.90, descricao: 'Suco natural de laranja, limão, maracujá ou abacaxi. Garrafa 500ml.' },
    ],
  },
  {
    nome: 'Café & Prosa',
    descricao: 'Cafeteria especial com grãos selecionados, bolos artesanais e ambiente aconchegante.',
    categoria: 'Cafeteria',

    foto: 'https://images.unsplash.com/photo-1554118811-1e0d58224f24?w=400',
    produtos: [
      { nome: 'Café Expresso', preco: 5.90, descricao: 'Expresso curto com grãos 100% arábica moídos na hora. Extração no momento.' },
      { nome: 'Cappuccino Cremoso', preco: 9.90, descricao: 'Cappuccino com leite vaporizado, chocolate em pó, canela e biscoito.' },
      { nome: 'Latte Macchiato', preco: 11.90, descricao: 'Leite vaporizado com café expresso, finalizado com espuma de leite.' },
      { nome: 'Mocha Chocolate', preco: 12.90, descricao: 'Café expresso com chocolate belga derretido e leite vaporizado. Chantilly.' },
      { nome: 'Chá Gelado de Frutas', preco: 8.50, descricao: 'Chá gelado de frutas vermelhas com hortelã e limão siciliano.' },
      { nome: 'Pão de Queijo Recheado', preco: 7.90, descricao: 'Pão de queijo recheado com catupiry ou requeijão. Assado na hora.' },
      { nome: 'Torta de Limão', preco: 10.90, descricao: 'Torta de limão com base de biscoito, mousse de limão e merengue.' },
      { nome: 'Cookie de Chocolate', preco: 6.50, descricao: 'Cookie artesanal de chocolate belga com nozes. Crocante por fora e macio por dentro.' },
      { nome: 'Sanduíche Natural', preco: 14.90, descricao: 'Sanduíche natural de frango com cream cheese, alface, cenoura e tomate seco.' },
      { nome: 'Suco Verde Detox', preco: 9.90, descricao: 'Suco detox de couve, gengibre, limão, maçã e hortelã. Garrafa 400ml.' },
    ],
  },
];

// ─── Função auxiliar para gerar código de desconto opcional ─────────────────
function randomPreco() {
  return Math.floor(Math.random() * 30) + 1;
}

// ─── Seed principal ─────────────────────────────────────────────────────────
async function main() {
  console.log(`Iniciando seed de ${LOJAS.length} lojas em ${CIDADE}...\n`);

  let totalProdutos = 0;

  for (let indiceLoja = 0; indiceLoja < LOJAS.length; indiceLoja++) {
    const loja = LOJAS[indiceLoja];
    const uid = `seed_toledo_loja_${indiceLoja + 1}`;
    const email = `loja${indiceLoja + 1}.toledo@dipertin.seed`;

    console.log(`[${indiceLoja + 1}/${LOJAS.length}] ${loja.nome}...`);

    // Cria doc em users (dispara trigger → lojas_public)
    await db.collection('users').doc(uid).set(
      {
        email,
        nome: loja.nome,
        nome_loja: loja.nome,
        descricao: loja.descricao,
        role: 'lojista',
        tipoUsuario: 'lojista',
        cidade: CIDADE,
        status_loja: 'aprovada',
        ativo: true,
        loja_aberta: true,
        telefone: `(45) 9${String(9000 + indiceLoja).padStart(4, '0')}-${String(1000 + indiceLoja).padStart(4, '0')}`,
        categoria: loja.categoria,
        horarios: horariosCompleto,
        foto_perfil: loja.foto,
        imagem: loja.foto,
        endereco_cidade: CIDADE,
        uf: 'PR',
        endereco: `Rua ${loja.nome.split(' ')[0]}, ${100 + indiceLoja * 100} - Centro`,
        latitude: -24.713 + (indiceLoja * 0.001),
        longitude: -53.743 + (indiceLoja * 0.001),
        data_criacao: admin.firestore.FieldValue.serverTimestamp(),
        sincronizado_em: admin.firestore.FieldValue.serverTimestamp(),
        seed_uid: uid,
      },
      { merge: true },
    );

    // Cria diretamente em lojas_public (garante visibilidade imediata)
    await db.collection('lojas_public').doc(uid).set(
      {
        loja_nome: loja.nome,
        nome_loja: loja.nome,
        nome: loja.nome,
        descricao: loja.descricao,
        cidade: CIDADE,
        endereco_cidade: CIDADE,
        uf: 'PR',
        status_loja: 'aprovada',
        loja_aberta: true,
        categoria: loja.categoria,
        horarios: horariosCompleto,
        foto_perfil: loja.foto,
        imagem: loja.foto,
        endereco: `Rua ${loja.nome.split(' ')[0]}, ${100 + indiceLoja * 100} - Centro`,
        latitude: -24.713 + (indiceLoja * 0.001),
        longitude: -53.743 + (indiceLoja * 0.001),
        rating_media: 4.5,
        total_avaliacoes: 0,
        sincronizado_em: admin.firestore.FieldValue.serverTimestamp(),
        tipos_entrega_permitidos: ['bicicleta', 'moto', 'carro'],
      },
      { merge: true },
    );

    // Cria os 10 produtos
    const batch = db.batch();
    for (let p = 0; p < loja.produtos.length; p++) {
      const prod = loja.produtos[p];
      const produtoId = `seed_toledo_p${indiceLoja + 1}_${String(p + 1).padStart(2, '0')}`;
      const fotos = [
        `https://images.unsplash.com/photo-${1546069901 + p}?w=400`,
        `https://images.unsplash.com/photo-${1546069901 + p + 100}?w=400`,
      ];

      const produtoRef = db.collection('produtos').doc(produtoId);
      batch.set(
        produtoRef,
        {
          lojista_id: uid,
          nome: prod.nome,
          descricao: prod.descricao,
          preco: prod.preco,
          oferta: null,
          categoria_nome: loja.categoria,
          imagens: [loja.foto],
          tipo_venda: 'imediata',
          estoque_qtd: 50 + Math.floor(Math.random() * 100),
          ativo: true,
          cidade: CIDADE_LOWER,
          data_criacao: admin.firestore.FieldValue.serverTimestamp(),
          total_vendas: Math.floor(Math.random() * 20),
        },
        { merge: true },
      );
      totalProdutos++;
    }
    await batch.commit();

    console.log(`  → ${loja.produtos.length} produtos criados.`);
  }

  console.log('\n═══════════════════════════════════════');
  console.log(`✅ Seed concluído!`);
  console.log(`📌 ${LOJAS.length} lojas criadas em ${CIDADE}`);
  console.log(`📌 ${totalProdutos} produtos no total`);
  console.log('📌 Dados visíveis na vitrine (Toledo-PR)');
  console.log('═══════════════════════════════════════');

  process.exit(0);
}

main().catch((err) => {
  console.error('Erro durante seed:', err);
  process.exit(1);
});

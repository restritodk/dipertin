# Compra por encomenda — arquitetura (Fase 0 + Fase 1 + Fase 2 + Fase 3)

## Princípios

- **Não alterar** o pipeline existente de `notification_dispatcher`, FCM, canais ou payloads.
- Avisos ao lojista/cliente nesta fase usam o padrão **`alerta_*`** no documento `users/{uid}` (consumido por `StreamBuilder`), igual ao conceito de `alerta_tipos_entrega_incompat`.
- Pedidos **tradicionais** (`tipo_venda != encomenda`) permanecem iguais.
- Identificação do produto: campo já existente em `produtos`: **`tipo_venda`** = `encomenda` (painel web e app lojista). No app cliente derivamos **`ehEncomenda`** ao montar o carrinho.

## Coleção `encomendas/{id}`

Escrita **somente via Cloud Functions** (Admin SDK). Leitura permitida a cliente dono ou loja dona (`loja_id`), conforme `firestore.rules`.

Campos principais (Fase 1):

| Campo | Descrição |
|-------|-----------|
| `cliente_id`, `loja_id` | Participantes |
| `status_negociacao` | Ver `lib/constants/encomenda_negociacao_status.dart` |
| `itens` | Snapshot `{ id_produto, nome, preco_ref, quantidade, imagem? }[]` |
| `mensagem_cliente` | Texto inicial opcional |
| `tipo_entrega`, `endereco_entrega`, `taxa_entrega_snapshot` | Contexto logístico informado na abertura |
| `valor_total_referencia`, `valor_entrada_loja`, `observacoes_loja` | Proposta da loja |
| `entrada_contraproposta_cliente`, `mensagem_contraproposta_cliente` | Contraproposta |
| `pedido_entrada_id` | ID em `pedidos` criado para cobrar só a entrada (PIX/cartão existentes) |
| `historico` | Lista curta de eventos `{ em, tipo, texto }` para timeline leve |
| `criado_em`, `atualizado_em` | Auditoria |

## Fluxo Fase 1

1. Cliente com **sacola só de encomenda**, uma loja, forma **Encomenda** → tela de envio → callable **`encomendaClienteCriar`** → `aguardando_negociacao`.
2. Loja recebe **`alerta_encomenda`** → painel **Negociações de encomenda**.
3. Loja: aceitar negociação → **`encomendaLojaAceitarNegociacao`** → `negociacao_em_andamento`.
4. Loja envia proposta (`valor_total_referencia`, `valor_entrada_loja`, observações) → **`encomendaLojaEnviarProposta`** → `proposta_enviada` + alerta cliente.
5. Cliente **aceita** → **`encomendaClienteAceitarPropostaECriarPedidoEntrada`** → cria `pedidos` com `tipo_compra: encomenda`, valores da entrada, `status: aguardando_pagamento`, `notificarNovoPedido` **não** dispara (já comportamento atual para esse status).
6. Cliente paga entrada no **`CheckoutPagamentoScreen`** existente (PIX/cartão).
7. **Negociar valor**: callables **`encomendaClienteEnviarContraproposta`** / **`encomendaLojaResponderContraproposta`** (aceitar | recusar | contrapropor).

## Pedido da entrada (`pedidos`)

Campos adicionais para não misturar com pedido final:

- `tipo_compra: 'encomenda'`
- `encomenda_id`
- `encomenda_fase_financeira: 'entrada'`
- `valor_total_encomenda_referencia`, `valor_entrada_acordado`, `valor_restante_estimado`

Fases seguintes (produção, saldo final, entrega) evoluem este modelo sem reaproveitar `status` logístico até o pagamento final estar definido.

## Índices

Consultas por `cliente_id` / `loja_id` + `atualizado_em` desc — ver `firestore.indexes.json`.

## Fluxo Fase 2 (entrada paga → produção → saldo → logística normal)

Novos valores em `encomendas.status_negociacao`:

| Valor | Significado |
|-------|-------------|
| `entrada_paga_em_producao` | MP confirmou a entrada; loja produz sem push de «novo pedido» |
| `saldo_final_aguardando_pgto` | Callable criou `pedidos` do saldo (`aguardando_pagamento`) |
| `em_execucao_logistica` | Saldo pago; pedido principal virou `pendente` e segue fluxo normal |

Comportamento backend:

1. **Webhook MP** — pagamento da entrada: pedido `tipo_compra=encomenda`, `encomenda_fase_financeira=entrada` → status **`encomenda_entrada_paga`** (não `pendente`); **não** chama `enviarNovoPedidoParaLoja`; roda `sincronizarEncomendaAposPagamentoEntrada` (`alerta_encomenda` / `alerta_encomenda_cliente`).
2. **`processarFinanceiroPedidoOnCreate`** — pedidos só de entrada **não** recebem split completo (`financeiro_skip_motivo`).
3. **Callable `encomendaLojaCriarPedidoSaldoFinal`** — exige `entrada_paga_em_producao` e pedido de entrada em `encomenda_entrada_paga`; cria pedido do saldo; atualiza negociação e alerta cliente.
4. **Webhook MP** — pagamento do saldo: pedido → **`pendente`**; **mantém** `enviarNovoPedidoParaLoja`; `sincronizarEncomendaAposPagamentoSaldoFinal` → `em_execucao_logistica`.
5. **`notificarClienteStatusPedido`** — ignora transição `aguardando_pagamento` → `encomenda_entrada_paga` (sem push redundante ao cliente).

App mobile: aba **Novos** do lojista inclui `encomenda_entrada_paga` com ação **Gerar cobrança do saldo**; telas de encomenda (cliente/loja) exibem os novos estados e checkout do saldo.

Pedidos de entrada antigos já gravados como `pendente` **não** são migrados automaticamente.

## Fluxo Fase 3 (paridade painel web + monitor admin)

- **Painel lojista (`lojista_meus_pedidos_screen`)**: exibe o status **`encomenda_entrada_paga`** com rótulo e cor dedicados; chip **Encomenda** nos cards quando `tipo_compra == encomenda`; no diálogo do pedido, banner + botão **Gerar cobrança do saldo** chama a callable **`encomendaLojaCriarPedidoSaldoFinal`** (mesma regra que o app mobile).
- **Negociações no painel web**: rota **`/negociacoes_encomenda`** (`LojistaNegociacoesEncomendaScreen`) — lista Firestore `encomendas` por `loja_id`; detalhe (`LojistaEncomendaDetalhePainelScreen`) com as mesmas callables do app (`encomendaLojaAceitarNegociacao`, `encomendaLojaEnviarProposta`, `encomendaLojaResponderContraproposta`, `encomendaLojaCriarPedidoSaldoFinal`). Menu lateral: **Negociações de encomenda**. Colaborador nível I também acessa (mesma regra de «Meus pedidos»).
- **Monitor de pedidos (staff)**: filtro e KPI **Enc. produção** para localizar pedidos de encomenda em fase de produção (entrada paga, antes do saldo).

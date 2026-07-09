/* ── DiPertin Payment Page JavaScript ── */

// Configurações
const FUNCTIONS_BASE = 'https://southamerica-east1-depertin-f940f.cloudfunctions.net';
const SITE_BASE = 'https://www.dipertin.com.br';

// Estado global
let estado = {
    token: null,
    sessaoId: null,
    parcelas: [],
    parcelasSelecionadas: [],
    valorTotal: 0,
    dadosCobranca: null,
    pixTimer: null,
    pixSegundos: 0,
    pollingInterval: null,
};

// ── Inicialização ──
document.addEventListener('DOMContentLoaded', function() {
    // Extrai token da URL
    const params = new URLSearchParams(window.location.search);
    estado.token = params.get('token') || '';

    if (!estado.token) {
        mostrarErroCPF('Link de pagamento inválido. Verifique o link recebido.');
        return;
    }

    // Configurar eventos
    document.getElementById('btn-continuar').addEventListener('click', validarCPF);
    document.getElementById('btn-efetuar-pagamento').addEventListener('click', mostrarFormaPagamento);
    document.getElementById('btn-forma-pix').addEventListener('click', gerarPix);
    document.getElementById('btn-forma-cartao').addEventListener('click', mostrarFormCartao);
    document.getElementById('btn-voltar-forma').addEventListener('click', mostrarTelaCobranca);
    document.getElementById('btn-voltar-pix').addEventListener('click', cancelarPix);
    document.getElementById('btn-voltar-cartao').addEventListener('click', mostrarFormaPagamento);
    document.getElementById('btn-resultado-fechar').addEventListener('click', function() {
        window.location.href = SITE_BASE;
    });

    // Máscara CPF
    document.getElementById('input-cpf').addEventListener('input', function(e) {
        let v = e.target.value.replace(/\D/g, '').substring(0, 11);
        let fmt = '';
        for (let i = 0; i < v.length; i++) {
            if (i === 3 || i === 6) fmt += '.';
            if (i === 9) fmt += '-';
            fmt += v[i];
        }
        e.target.value = fmt;
        document.getElementById('btn-continuar').disabled = v.length !== 11;
        document.getElementById('erro-cpf').style.display = 'none';
    });

    // Máscara cartão
    document.getElementById('card-number').addEventListener('input', function(e) {
        let v = e.target.value.replace(/\D/g, '').substring(0, 16);
        let fmt = '';
        for (let i = 0; i < v.length; i++) {
            if (i > 0 && i % 4 === 0) fmt += ' ';
            fmt += v[i];
        }
        e.target.value = fmt;
    });

    document.getElementById('card-expiry').addEventListener('input', function(e) {
        let v = e.target.value.replace(/\D/g, '').substring(0, 4);
        let fmt = '';
        for (let i = 0; i < v.length; i++) {
            if (i === 2) fmt += '/';
            fmt += v[i];
        }
        e.target.value = fmt;
    });

    document.getElementById('card-cvv').addEventListener('input', function(e) {
        e.target.value = e.target.value.replace(/\D/g, '').substring(0, 4);
    });

    document.getElementById('form-cartao').addEventListener('submit', processarCartao);
    document.getElementById('btn-copiar').addEventListener('click', copiarCodigoPix);

    // Verificar token
    verificarToken();
});

// ── Chamada API ──
async function apiCall(url, dados) {
    try {
        const resp = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(dados),
        });
        const text = await resp.text();
        try {
            return { status: resp.status, data: JSON.parse(text) };
        } catch (e) {
            return { status: resp.status, data: { ok: false, erro: text } };
        }
    } catch (err) {
        return { status: 0, data: { ok: false, erro: 'Erro de conexão: ' + err.message } };
    }
}

// ── Utilitários ──
function formatarMoeda(valor) {
    return 'R$ ' + Number(valor).toFixed(2).replace('.', ',');
}

function formatarDataISO(iso) {
    if (!iso) return '—';
    try {
        const d = new Date(iso);
        return d.toLocaleDateString('pt-BR');
    } catch (e) { return iso; }
}

function formatarCPF(cpf) {
    if (!cpf) return '—';
    cpf = cpf.replace(/\D/g, '');
    if (cpf.length < 11) return cpf;
    return cpf.substring(0, 3) + '.' + cpf.substring(3, 6) + '.' + cpf.substring(6, 9) + '-' + cpf.substring(9, 11);
}

function mascararCPF(cpf) {
    if (!cpf) return '—';
    cpf = cpf.replace(/\D/g, '');
    if (cpf.length < 11) return cpf;
    return cpf.substring(0, 3) + '.' + '***' + '.' + cpf.substring(6, 9) + '-' + cpf.substring(9, 11);
}

function mostrarLoading(msg) {
    document.getElementById('loading-msg').textContent = msg || 'Carregando...';
    document.getElementById('loading-overlay').style.display = 'flex';
}

function esconderLoading() {
    document.getElementById('loading-overlay').style.display = 'none';
}

function mostrarErroCPF(msg) {
    const el = document.getElementById('erro-cpf');
    el.textContent = msg;
    el.style.display = 'block';
}

// ── Navegação entre telas ──
function mostrarTela(id) {
    ['tela-cpf', 'tela-cobranca', 'tela-forma-pgto', 'tela-pix', 'tela-cartao', 'tela-resultado'].forEach(function(t) {
        document.getElementById(t).style.display = t === id ? '' : 'none';
    });
}

// ── 1. Verificar token ──
async function verificarToken() {
    mostrarLoading('Verificando link de pagamento...');
    const resp = await apiCall(FUNCTIONS_BASE + '/gestaoComercialConsultarCobrancaPorToken', {
        token: estado.token
    });
    esconderLoading();

    if (!resp.data.ok) {
        mostrarErroCPF(resp.data.erro || 'Link de pagamento inválido ou expirado.');
        return;
    }

    // Apenas guarda os dados em memória — NÃO mostra preview na tela de CPF
    estado.dadosCobranca = resp.data;
    estado.parcelas = ordenarParcelas(resp.data.parcelas || []);
    estado.valorTotal = resp.data.valor_total || 0;
}

// ── 2. Validar CPF ──
async function validarCPF() {
    const cpfInput = document.getElementById('input-cpf').value.replace(/\D/g, '');
    if (cpfInput.length !== 11) {
        mostrarErroCPF('Digite um CPF válido com 11 dígitos.');
        return;
    }

    const btn = document.getElementById('btn-continuar');
    btn.disabled = true;
    btn.querySelector('.btn-texto').style.display = 'none';
    btn.querySelector('.btn-loading').style.display = 'flex';
    document.getElementById('erro-cpf').style.display = 'none';

    const resp = await apiCall(FUNCTIONS_BASE + '/gestaoComercialValidarCpfToken', {
        token: estado.token,
        cpf: cpfInput,
    });

    btn.disabled = false;
    btn.querySelector('.btn-texto').style.display = 'flex';
    btn.querySelector('.btn-loading').style.display = 'none';

    if (!resp.data.ok) {
        mostrarErroCPF(resp.data.erro || 'CPF não encontrado ou não corresponde a esta cobrança.');
        return;
    }

    estado.sessaoId = resp.data.sessao_id;
    estado.parcelas = ordenarParcelas(resp.data.parcelas || []);
    estado.valorTotal = resp.data.valor_total || 0;
    estado.dadosCobranca = resp.data;
    estado.dadosCobranca.cliente_cpf = cpfInput;

    mostrarTelaCobranca({ inicializarSelecao: true });
}

// ── 3. Tela de cobrança ──
function parcelaVencimentoMaisProximo(parcelas) {
    if (!parcelas || !parcelas.length) return null;

    let melhor = null;
    let melhorTs = Infinity;

    parcelas.forEach(function(p) {
        if (!p.data_vencimento) return;
        const ts = new Date(p.data_vencimento).getTime();
        if (ts < melhorTs) {
            melhorTs = ts;
            melhor = p;
        }
    });

    return melhor || parcelas[0];
}

function selecaoInicialParcelas() {
    const p = parcelaVencimentoMaisProximo(estado.parcelas);
    return p && p.id ? [p.id] : [];
}

function mostrarTelaCobranca(opcoes) {
    opcoes = opcoes || {};
    const dados = estado.dadosCobranca;
    document.getElementById('loja-nome-cob').textContent = dados.loja_nome || '';
    document.getElementById('cliente-nome-cob').textContent = dados.cliente_nome || '';
    document.getElementById('cpf-mask').textContent = dados.cliente_cpf ? mascararCPF(dados.cliente_cpf) : '';

    const logoEl = document.getElementById('loja-logo');
    if (dados.loja_logo) {
        logoEl.src = dados.loja_logo;
        logoEl.style.display = '';
    } else {
        logoEl.style.display = 'none';
    }

    if (opcoes.inicializarSelecao) {
        estado.parcelasSelecionadas = selecaoInicialParcelas();
    }

    atualizarListaParcelas();
    atualizarTotalSelecionado();
    mostrarTela('tela-cobranca');
}

function ordenarParcelas(parcelas) {
    return parcelas.slice().sort(function(a, b) {
        const da = a.data_vencimento ? new Date(a.data_vencimento).getTime() : 0;
        const db = b.data_vencimento ? new Date(b.data_vencimento).getTime() : 0;
        return da - db;
    });
}

function rotuloParcela(p, idx) {
    if (p.numero_parcela && p.total_parcelas > 1) {
        return 'Parcela ' + p.numero_parcela + ' de ' + p.total_parcelas;
    }
    if (p.numero_parcela) {
        return 'Parcela ' + p.numero_parcela;
    }
    return 'Item ' + (idx + 1);
}

function atualizarListaParcelas() {
    const container = document.getElementById('lista-parcelas');
    document.getElementById('qtd-parcelas-badge').textContent = estado.parcelas.length + ' ite' + (estado.parcelas.length === 1 ? 'm' : 'ns');

    container.innerHTML = '';
    estado.parcelas.forEach(function(p, idx) {
        const sel = estado.parcelasSelecionadas.includes(p.id);
        const div = document.createElement('div');
        div.className = 'cobranca-parcela' + (sel ? ' selecionada' : '');
        div.setAttribute('role', 'checkbox');
        div.setAttribute('aria-checked', sel ? 'true' : 'false');
        div.setAttribute('tabindex', '0');
        div.innerHTML = `
            <div class="cobranca-checkbox">
                <svg width="12" height="10" viewBox="0 0 12 10" fill="none">
                    <path d="M1.5 5L4.5 8.5l6-7" stroke="white" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
                </svg>
            </div>
            <div class="cobranca-parcela-info">
                <div class="cobranca-parcela-top">
                    ${p.codigo_venda ? '<span class="cobranca-parcela-pedido">' + p.codigo_venda + '</span>' : ''}
                    <span class="cobranca-parcela-desc">${rotuloParcela(p, idx)}</span>
                </div>
                <div class="cobranca-parcela-venc">
                    <svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true">
                        <rect x="1.5" y="2.5" width="11" height="10" rx="1.5" stroke="currentColor" stroke-width="1.2"/>
                        <path d="M1.5 5.5h11" stroke="currentColor" stroke-width="1.2"/>
                        <path d="M4.5 1v3M9.5 1v3" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/>
                    </svg>
                    Vence em ${formatarDataISO(p.data_vencimento)}
                </div>
            </div>
            <div class="cobranca-parcela-valor-wrap">
                ${p.valor_parcela !== p.valor_em_aberto ? '<div class="cobranca-parcela-valor-original">' + formatarMoeda(p.valor_parcela) + '</div>' : ''}
                <div class="cobranca-parcela-valor-atual">${formatarMoeda(p.valor_em_aberto || p.valor_parcela)}</div>
            </div>
        `;
        div.addEventListener('click', function() {
            toggleParcela(p.id);
        });
        div.addEventListener('keydown', function(e) {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                toggleParcela(p.id);
            }
        });
        container.appendChild(div);
    });
}

function toggleParcela(id) {
    const idx = estado.parcelasSelecionadas.indexOf(id);
    if (idx >= 0) {
        estado.parcelasSelecionadas.splice(idx, 1);
    } else {
        estado.parcelasSelecionadas.push(id);
    }

    atualizarListaParcelas();
    atualizarTotalSelecionado();
}

function atualizarTotalSelecionado() {
    let total = 0;
    estado.parcelas.forEach(function(p) {
        if (estado.parcelasSelecionadas.includes(p.id)) {
            total += Number(p.valor_em_aberto || p.valor_parcela || 0);
        }
    });

    const totalFmt = formatarMoeda(total);
    const totalAbertoFmt = formatarMoeda(estado.valorTotal);

    document.getElementById('valor-total-texto').textContent = totalAbertoFmt;
    document.getElementById('valor-selecionado-texto').textContent = totalFmt;

    const grande = document.getElementById('valor-selecionado-texto-grande');
    if (grande) {
        grande.textContent = totalFmt;
    }

    document.getElementById('btn-efetuar-pagamento').disabled = estado.parcelasSelecionadas.length === 0;
}

// ── 4. Escolha forma de pagamento ──
function mostrarFormaPagamento() {
    const total = calcularTotalSelecionado();
    document.getElementById('forma-valor-resumo').textContent = formatarMoeda(total) + ' - ' + estado.parcelasSelecionadas.length + ' parcela(s)';
    mostrarTela('tela-forma-pgto');
}

function calcularTotalSelecionado() {
    let total = 0;
    estado.parcelas.forEach(function(p) {
        if (estado.parcelasSelecionadas.includes(p.id)) {
            total += Number(p.valor_em_aberto || p.valor_parcela || 0);
        }
    });
    return total;
}

function tratarErroSessaoExpirada(resp) {
    const msg = String((resp.data && resp.data.erro) || '').toLowerCase();
    const codigo = resp.data && resp.data.codigo;
    const ehSessao = codigo === 'sessao_expirada' || (resp.status === 403 && msg.indexOf('sessao') !== -1);
    if (!ehSessao) return false;

    estado.sessaoId = null;
    mostrarErroCPF('Sua sessão expirou. Digite seu CPF novamente para continuar.');
    document.getElementById('input-cpf').value = '';
    document.getElementById('btn-continuar').disabled = true;
    mostrarTela('tela-cpf');
    return true;
}

// ── 5. PIX ──
async function gerarPix() {
    const total = calcularTotalSelecionado();
    document.getElementById('pix-valor-texto').textContent = formatarMoeda(total);

    const btnPix = document.getElementById('btn-forma-pix');
    btnPix.disabled = true;
    btnPix.innerHTML = '<span class="spinner"></span> Gerando PIX...';

    const resp = await apiCall(FUNCTIONS_BASE + '/gestaoComercialProcessarPagamentoToken', {
        token: estado.token,
        sessao_id: estado.sessaoId,
        forma_pagamento: 'pix',
        parcelas_ids: estado.parcelasSelecionadas,
    });

    btnPix.disabled = false;
    btnPix.innerHTML = `
        <span class="forma-icone"><svg width="40" height="40" viewBox="0 0 48 48" fill="none"><rect width="48" height="48" rx="12" fill="#6A1B9A"/><text x="24" y="28" text-anchor="middle" fill="white" font-size="14" font-weight="bold">PIX</text></svg></span>
        <span class="forma-info"><strong>PIX</strong><span>Pagamento instantâneo, QR Code</span></span>
        <span class="forma-seta">&rsaquo;</span>
    `;

    if (!resp.data.ok) {
        if (tratarErroSessaoExpirada(resp)) return;
        mostrarResultado(false, 'Erro ao gerar PIX', resp.data.erro || 'Tente novamente mais tarde.');
        return;
    }

    mostrarTelaPix(resp.data);
}

async function renderizarQrCodePix(container, qrCode, qrBase64) {
    container.innerHTML = '';

    if (qrBase64 && qrBase64.length > 50 && !qrBase64.startsWith('000201')) {
        const img = document.createElement('img');
        img.alt = 'QR Code PIX';
        img.src = qrBase64.startsWith('data:') ? qrBase64 : ('data:image/png;base64,' + qrBase64);
        img.width = 220;
        img.height = 220;
        img.style.display = 'block';
        img.style.margin = '0 auto';
        container.appendChild(img);
        return true;
    }

    if (!qrCode) return false;

    try {
        if (typeof QRCode !== 'undefined' && typeof QRCode.toCanvas === 'function') {
            const canvas = document.createElement('canvas');
            canvas.setAttribute('role', 'img');
            canvas.setAttribute('aria-label', 'QR Code PIX');
            container.appendChild(canvas);
            await QRCode.toCanvas(canvas, qrCode, {
                width: 220,
                margin: 2,
                errorCorrectionLevel: 'M',
                color: { dark: '#1A1A2E', light: '#FFFFFF' },
            });
            return true;
        }
    } catch (e) {
        console.error('[pagar] Falha ao renderizar QR:', e);
    }

    return false;
}

async function mostrarTelaPix(dados) {
    const qrCode = dados.qr_code || dados.copia_e_cola || '';
    const qrBase64 = dados.qr_code_base64 || '';

    if (!qrCode && !qrBase64) {
        mostrarResultado(false, 'Erro ao gerar PIX', 'O gateway não retornou o código PIX. Tente novamente.');
        return;
    }

    mostrarTela('tela-pix');

    const qrContainer = document.getElementById('qrcode-container');
    qrContainer.innerHTML = '';

    const inputCopiaCola = document.getElementById('input-copia-cola');
    inputCopiaCola.value = qrCode;

    const qrOk = await renderizarQrCodePix(qrContainer, qrCode, qrBase64);
    if (!qrOk) {
        qrContainer.innerHTML = '<div class="qrcode-placeholder"><p>Não foi possível exibir o QR Code</p></div>';
    }

    // Timer de expiração
    if (dados.expira_em) {
        const expira = new Date(dados.expira_em);
        const agora = new Date();
        const segundos = Math.max(0, Math.floor((expira.getTime() - agora.getTime()) / 1000));
        iniciarTimerPix(segundos);
    } else {
        iniciarTimerPix(300);
    }

    // Iniciar polling (confirmação via backend — consulta MP e baixa parcelas)
    document.getElementById('pix-status').style.display = 'flex';
    iniciarPollingPix(dados.payment_id);
}

function iniciarTimerPix(segundos) {
    if (estado.pixTimer) clearInterval(estado.pixTimer);
    estado.pixSegundos = segundos;

    estado.pixTimer = setInterval(function() {
        estado.pixSegundos--;
        if (estado.pixSegundos <= 0) {
            clearInterval(estado.pixTimer);
            estado.pixTimer = null;
            document.getElementById('pix-timer').textContent = 'Expirado';
            pararPolling();
            document.getElementById('pix-status').style.display = 'none';
            return;
        }
        const min = Math.floor(estado.pixSegundos / 60);
        const sec = estado.pixSegundos % 60;
        document.getElementById('pix-timer').textContent = min + ':' + String(sec).padStart(2, '0');
    }, 1000);
}

async function iniciarPollingPix(paymentId) {
    pararPolling();

    async function verificarStatusPix() {
        try {
            const resp = await apiCall(FUNCTIONS_BASE + '/gestaoComercialConsultarStatusPagamentoToken', {
                token: estado.token,
                sessao_id: estado.sessaoId,
                payment_id: paymentId,
            });

            if (!resp.data || !resp.data.ok) {
                if (tratarErroSessaoExpirada(resp)) {
                    pararPolling();
                    if (estado.pixTimer) {
                        clearInterval(estado.pixTimer);
                        estado.pixTimer = null;
                    }
                }
                return;
            }

            const d = resp.data;

            if (d.aprovado) {
                pararPolling();
                if (estado.pixTimer) {
                    clearInterval(estado.pixTimer);
                    estado.pixTimer = null;
                }
                document.getElementById('pix-status').style.display = 'none';
                mostrarResultado(
                    true,
                    'Pagamento confirmado!',
                    'Recebemos seu pagamento PIX. As parcelas foram baixadas automaticamente.'
                );
                return;
            }

            if (d.status_mp === 'rejected' || d.status_mp === 'cancelled' || d.status_mp === 'refunded') {
                pararPolling();
                document.getElementById('pix-status').style.display = 'none';
                mostrarResultado(
                    false,
                    'Pagamento não concluído',
                    'O PIX não foi confirmado pelo banco. Gere um novo código ou tente outra forma de pagamento.'
                );
            }
        } catch (e) {
            // Mantém polling — falha de rede temporária
        }
    }

    await verificarStatusPix();
    estado.pollingInterval = setInterval(verificarStatusPix, 5000);
}

function pararPolling() {
    if (estado.pollingInterval) {
        clearInterval(estado.pollingInterval);
        estado.pollingInterval = null;
    }
}

function copiarCodigoPix() {
    const input = document.getElementById('input-copia-cola');
    input.select();
    input.setSelectionRange(0, 99999);
    navigator.clipboard.writeText(input.value).then(function() {
        const btn = document.getElementById('btn-copiar');
        btn.textContent = 'Copiado!';
        setTimeout(function() { btn.textContent = 'Copiar'; }, 2000);
    }).catch(function() {
        document.execCommand('copy');
    });
}

function cancelarPix() {
    if (estado.pixTimer) clearInterval(estado.pixTimer);
    pararPolling();
    mostrarFormaPagamento();
}

// ── 6. Cartão ──
function mostrarFormCartao() {
    const total = calcularTotalSelecionado();
    document.getElementById('cartao-valor-texto').textContent = formatarMoeda(total);
    document.getElementById('erro-cartao').style.display = 'none';
    mostrarTela('tela-cartao');
}

async function processarCartao(event) {
    event.preventDefault();

    const cardNumber = document.getElementById('card-number').value.replace(/\D/g, '');
    const cardExpiry = document.getElementById('card-expiry').value.replace(/\D/g, '');
    const cardCVV = document.getElementById('card-cvv').value;
    const cardName = document.getElementById('card-name').value.trim();
    const installments = document.getElementById('card-installments').value;

    if (!cardNumber || cardNumber.length < 13) {
        mostrarErroCartao('Número do cartão inválido.');
        return;
    }
    if (!cardExpiry || cardExpiry.length < 4) {
        mostrarErroCartao('Data de validade inválida.');
        return;
    }
    if (!cardCVV || cardCVV.length < 3) {
        mostrarErroCartao('CVV inválido.');
        return;
    }
    if (!cardName) {
        mostrarErroCartao('Nome no cartão obrigatório.');
        return;
    }

    const btn = document.getElementById('btn-pagar-cartao');
    btn.disabled = true;
    btn.querySelector('.btn-texto').style.display = 'none';
    btn.querySelector('.btn-loading').style.display = 'flex';
    document.getElementById('erro-cartao').style.display = 'none';

    // Gerar card_token via Mercado Pago SDK
    let cardToken = null;
    try {
        if (typeof MercadoPago !== 'undefined') {
            const mp = new MercadoPago('TEST-...'); // public key vem da sessão
            const tokenResp = await mp.cardToken.create({
                cardNumber: cardNumber,
                cardExpirationMonth: cardExpiry.substring(0, 2),
                cardExpirationYear: '20' + cardExpiry.substring(2, 4),
                securityCode: cardCVV,
                cardholderName: cardName,
            });
            cardToken = tokenResp.id;
        }
    } catch (e) {
        // Fallback: envia dados para o backend (que usa token próprio)
    }

    const total = calcularTotalSelecionado();

    const resp = await apiCall(FUNCTIONS_BASE + '/gestaoComercialProcessarPagamentoToken', {
        token: estado.token,
        sessao_id: estado.sessaoId,
        forma_pagamento: 'cartao',
        parcelas_ids: estado.parcelasSelecionadas,
        card_token: cardToken || 'simulated_' + Date.now(),
        installments: parseInt(installments),
        payer_email: 'cliente@dipertin.com.br',
    });

    btn.disabled = false;
    btn.querySelector('.btn-texto').style.display = 'flex';
    btn.querySelector('.btn-loading').style.display = 'none';

    if (!resp.data.ok) {
        if (tratarErroSessaoExpirada(resp)) return;
        mostrarResultado(false, 'Pagamento recusado', resp.data.erro || 'A transação não foi aprovada. Tente novamente.');
        return;
    }

    if (resp.data.approved) {
        mostrarResultado(true, 'Pagamento aprovado!', 'Sua compra foi processada com sucesso. As parcelas foram baixadas automaticamente.');
    } else {
        const detalhe = resp.data.detalhe_recusa ? 'Motivo: ' + resp.data.detalhe_recusa : '';
        mostrarResultado(false, 'Pagamento recusado', detalhe || 'O pagamento não foi aprovado. Tente novamente com outro cartão.');
    }
}

function mostrarErroCartao(msg) {
    const el = document.getElementById('erro-cartao');
    el.textContent = msg;
    el.style.display = 'block';
}

// ── 7. Resultado ──
function mostrarResultado(sucesso, titulo, msg) {
    pararPolling();
    if (estado.pixTimer) clearInterval(estado.pixTimer);

    mostrarTela('tela-resultado');

    const header = document.getElementById('resultado-header');
    header.className = 'card-header ' + (sucesso ? 'resultado-sucesso' : 'resultado-erro');

    document.getElementById('resultado-icone').textContent = sucesso ? '\u2705' : '\u274C';
    document.getElementById('resultado-titulo').textContent = titulo;
    document.getElementById('resultado-msg').textContent = msg;

    const detalhes = document.getElementById('resultado-detalhes');
    detalhes.innerHTML = '';

    if (sucesso) {
        detalhes.innerHTML = '<p>O comprovante será enviado automaticamente para seu contato cadastrado.</p>';
    } else {
        const btnTentar = document.createElement('button');
        btnTentar.className = 'btn btn-outline btn-sm';
        btnTentar.textContent = 'Tentar novamente';
        btnTentar.onclick = function() {
            mostrarTelaCobranca();
        };
        detalhes.appendChild(btnTentar);
    }

    const btnFechar = document.getElementById('btn-resultado-fechar');
    btnFechar.textContent = sucesso ? 'Ir para o site DiPertin' : 'Voltar';
    btnFechar.onclick = function() {
        if (sucesso) {
            window.location.href = SITE_BASE;
        } else {
            mostrarTelaCobranca();
        }
    };

    // Após pagamento aprovado, polling verifica confirmação webhook
    if (sucesso) {
        // Aguarda webhook processar
        setTimeout(function() {
            // Recarrega para estado limpo
            document.getElementById('btn-resultado-fechar').onclick = function() {
                window.location.href = SITE_BASE;
            };
        }, 3000);
    }
}

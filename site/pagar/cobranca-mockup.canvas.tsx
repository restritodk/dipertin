import React from "react";

export default function CobrancaMockup() {
  const parcels = [
    { codigo: "PED-107755", vencimento: "10/07/2026", valor: "R$ 2,27" },
    { codigo: "PED-107755", vencimento: "10/08/2026", valor: "R$ 2,27" },
    { codigo: "PED-107755", vencimento: "10/09/2026", valor: "R$ 2,26" },
  ];

  return (
    <div style={styles.outerContainer}>
      <style>{css}</style>
      <div id="cobranca-mockup" className="cobranca-wrapper">
        {/* Background decorative elements */}
        <div className="bg-blob bg-blob-1" />
        <div className="bg-blob bg-blob-2" />
        <div className="bg-blob bg-blob-3" />

        {/* Top branding bar */}
        <div className="top-bar">
          <div className="top-bar-inner">
            <img
              src="https://www.dipertin.com.br/assets/logo-tela-login.png"
              alt="DiPertin"
              className="top-logo"
            />
            <span className="top-brand">DiPertin</span>
          </div>
        </div>

        {/* Main content area */}
        <div className="main-content">
          {/* Central card */}
          <div className="central-card">
            {/* Header */}
            <div className="card-header">
              <div className="orb orb-1" />
              <div className="orb orb-2" />
              <div className="orb orb-3" />

              <div className="header-left">
                <div className="header-brand-row">
                  <div className="header-logo-wrapper">
                    <img
                      src="https://www.dipertin.com.br/assets/logo-tela-login.png"
                      alt="DiPertin"
                      className="header-logo"
                    />
                  </div>
                  <div className="header-divider" />
                  <div className="header-store-info">
                    <span className="store-label">Loja</span>
                    <span className="store-name">Fran Artesanatos</span>
                  </div>
                </div>
                <div className="header-client-info">
                  <div className="client-avatar">
                    {getInitials("Eurico dos Santos Mota")}
                  </div>
                  <div className="client-details">
                    <span className="client-name">Eurico dos Santos Mota</span>
                    <span className="client-cpf">CPF 020.***.***-62</span>
                  </div>
                </div>
              </div>

              <div className="header-right">
                <div className="glass-card-total">
                  <div className="glass-label">Valor total em aberto</div>
                  <div className="glass-value">R$ 6,80</div>
                </div>
              </div>
            </div>

            {/* Body: 2 columns */}
            <div className="card-body">
              {/* Left column */}
              <div className="body-left">
                <div className="section-title-row">
                  <div className="section-icon-wrapper">
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#6A1B9A" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <rect x="3" y="4" width="18" height="18" rx="2" ry="2" />
                      <line x1="16" y1="2" x2="16" y2="6" />
                      <line x1="8" y1="2" x2="8" y2="6" />
                      <line x1="3" y1="10" x2="21" y2="10" />
                    </svg>
                  </div>
                  <h2 className="section-title">Itens em atraso</h2>
                  <span className="items-badge">3 itens</span>
                </div>

                <div className="parcels-list">
                  {parcels.map((p, i) => (
                    <div key={i} className="parcel-item">
                      <div className="parcel-checkbox">
                        <div className="checkbox-custom checked" />
                      </div>
                      <div className="parcel-info">
                        <span className="parcel-code">{p.codigo}</span>
                        <div className="parcel-date-row">
                          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#64748B" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                            <rect x="3" y="4" width="18" height="18" rx="2" ry="2" />
                            <line x1="16" y1="2" x2="16" y2="6" />
                            <line x1="8" y1="2" x2="8" y2="6" />
                            <line x1="3" y1="10" x2="21" y2="10" />
                          </svg>
                          <span className="parcel-date">Vence {p.vencimento}</span>
                        </div>
                      </div>
                      <div className="parcel-value-area">
                        <span className="parcel-value">{p.valor}</span>
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#94A3B8" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                          <polyline points="9 18 15 12 9 6" />
                        </svg>
                      </div>
                    </div>
                  ))}
                </div>

                {/* Bottom card */}
                <div className="bottom-info-card">
                  <div className="info-card-icon">
                    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#6A1B9A" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                      <rect x="3" y="4" width="18" height="18" rx="2" ry="2" />
                      <line x1="16" y1="2" x2="16" y2="6" />
                      <line x1="8" y1="2" x2="8" y2="6" />
                      <line x1="3" y1="10" x2="21" y2="10" />
                    </svg>
                  </div>
                  <div className="info-card-text">
                    <strong>Evite juros e negativas</strong>
                    <p>Quite suas parcelas em dia e mantenha seu nome limpo na praça.</p>
                  </div>
                </div>
              </div>

              {/* Right column */}
              <div className="body-right">
                <div className="summary-card">
                  <div className="summary-header">
                    <div className="summary-icon-wrapper">
                      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#6A1B9A" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                        <polyline points="14 2 14 8 20 8" />
                        <line x1="16" y1="13" x2="8" y2="13" />
                        <line x1="16" y1="17" x2="8" y2="17" />
                        <polyline points="10 9 9 9 8 9" />
                      </svg>
                    </div>
                    <span className="summary-title">Resumo da seleção</span>
                  </div>

                  <div className="summary-rows">
                    <div className="summary-row">
                      <span className="summary-label">Total selecionado</span>
                      <span className="summary-value">R$ 6,80</span>
                    </div>
                    <div className="summary-row">
                      <span className="summary-label">Taxas</span>
                      <span className="summary-value muted">R$ 0,00</span>
                    </div>
                  </div>

                  <div className="summary-divider" />

                  <div className="summary-total-row">
                    <span className="total-label">Total a pagar</span>
                    <span className="total-value">R$ 6,80</span>
                  </div>

                  <button className="pay-button">
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                      <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                      <path d="M7 11V7a5 5 0 0 1 10 0v4" />
                    </svg>
                    <span>Pagar agora</span>
                  </button>

                  <div className="secure-badge">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#64748B" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                      <path d="M7 11V7a5 5 0 0 1 10 0v4" />
                    </svg>
                    <span>Pagamento 100% seguro</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Footer */}
        <div className="footer-bar">
          <span>DiPertin &copy; 2026 &mdash; Pagamento de cobran&ccedil;a</span>
        </div>
      </div>
    </div>
  );
}

function getInitials(name: string) {
  return name
    .split(" ")
    .filter((_, i, a) => i === 0 || i === a.length - 1)
    .map((w) => w[0])
    .join("")
    .toUpperCase();
}

const css = `
  @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap');

  .cobranca-wrapper {
    font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    display: flex;
    flex-direction: column;
    align-items: center;
    min-height: 100vh;
    background: #F5F4F8;
    position: relative;
    overflow: hidden;
  }

  .cobranca-wrapper * {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
  }

  /* Background blobs */
  .bg-blob {
    position: fixed;
    border-radius: 50%;
    pointer-events: none;
    z-index: 0;
  }
  .bg-blob-1 {
    width: 600px;
    height: 600px;
    background: radial-gradient(circle, rgba(106,27,154,0.08) 0%, transparent 70%);
    top: -200px;
    right: -100px;
  }
  .bg-blob-2 {
    width: 500px;
    height: 500px;
    background: radial-gradient(circle, rgba(255,143,0,0.06) 0%, transparent 70%);
    bottom: -150px;
    left: -100px;
  }
  .bg-blob-3 {
    width: 400px;
    height: 400px;
    background: radial-gradient(circle, rgba(106,27,154,0.05) 0%, transparent 70%);
    bottom: 10%;
    right: 20%;
  }

  /* Top bar */
  .top-bar {
    width: 100%;
    background: transparent;
    padding: 20px 40px;
    z-index: 1;
    position: relative;
  }
  .top-bar-inner {
    max-width: 1120px;
    margin: 0 auto;
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .top-logo {
    height: 32px;
    width: auto;
  }
  .top-brand {
    font-size: 20px;
    font-weight: 700;
    color: #6A1B9A;
    letter-spacing: -0.02em;
  }

  /* Main content */
  .main-content {
    width: 100%;
    max-width: 1120px;
    padding: 0 24px;
    z-index: 1;
    position: relative;
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  /* Central card */
  .central-card {
    width: 100%;
    background: #FFFFFF;
    border-radius: 28px;
    box-shadow: 0 4px 24px rgba(0,0,0,0.06), 0 1px 4px rgba(0,0,0,0.04);
    overflow: hidden;
    transition: box-shadow 0.3s ease;
  }

  /* Card header */
  .card-header {
    position: relative;
    height: 180px;
    background: linear-gradient(135deg, #5B0DBA 0%, #6F18C8 35%, #7E22CE 65%, #9229C9 100%);
    padding: 28px 36px;
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    overflow: hidden;
  }

  /* Decorative orbs */
  .orb {
    position: absolute;
    border-radius: 50%;
    pointer-events: none;
  }
  .orb-1 {
    width: 280px;
    height: 280px;
    background: radial-gradient(circle, rgba(255,255,255,0.12) 0%, transparent 70%);
    top: -80px;
    right: 240px;
  }
  .orb-2 {
    width: 180px;
    height: 180px;
    background: radial-gradient(circle, rgba(255,255,255,0.08) 0%, transparent 70%);
    bottom: -40px;
    right: 80px;
  }
  .orb-3 {
    width: 120px;
    height: 120px;
    background: radial-gradient(circle, rgba(255,255,255,0.06) 0%, transparent 70%);
    top: 20px;
    right: -20px;
  }

  .header-left {
    position: relative;
    z-index: 1;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }
  .header-brand-row {
    display: flex;
    align-items: center;
    gap: 14px;
  }
  .header-logo-wrapper {
    width: 44px;
    height: 44px;
    background: rgba(255,255,255,0.15);
    border-radius: 12px;
    display: flex;
    align-items: center;
    justify-content: center;
    backdrop-filter: blur(4px);
  }
  .header-logo {
    height: 28px;
    width: auto;
  }
  .header-divider {
    width: 1px;
    height: 32px;
    background: rgba(255,255,255,0.25);
  }
  .header-store-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .store-label {
    font-size: 11px;
    font-weight: 500;
    color: rgba(255,255,255,0.6);
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }
  .store-name {
    font-size: 16px;
    font-weight: 600;
    color: #FFFFFF;
  }

  .header-client-info {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .client-avatar {
    width: 40px;
    height: 40px;
    background: rgba(255,255,255,0.2);
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 14px;
    font-weight: 700;
    color: #FFFFFF;
    backdrop-filter: blur(4px);
  }
  .client-details {
    display: flex;
    flex-direction: column;
    gap: 1px;
  }
  .client-name {
    font-size: 14px;
    font-weight: 600;
    color: #FFFFFF;
  }
  .client-cpf {
    font-size: 12px;
    color: rgba(255,255,255,0.6);
  }

  /* Glass card right */
  .header-right {
    position: relative;
    z-index: 1;
  }
  .glass-card-total {
    background: rgba(255,255,255,0.15);
    backdrop-filter: blur(12px);
    border: 1px solid rgba(255,255,255,0.2);
    border-radius: 16px;
    padding: 16px 24px;
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 200px;
  }
  .glass-label {
    font-size: 11px;
    font-weight: 500;
    color: rgba(255,255,255,0.7);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  .glass-value {
    font-size: 24px;
    font-weight: 700;
    color: #FFFFFF;
  }

  /* Card body */
  .card-body {
    display: flex;
    padding: 0;
    min-height: 400px;
  }

  /* Left column */
  .body-left {
    flex: 7;
    padding: 32px 36px;
    border-right: 1px solid #F1F0F6;
  }

  .section-title-row {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-bottom: 24px;
  }
  .section-icon-wrapper {
    width: 36px;
    height: 36px;
    background: #F5F0FF;
    border-radius: 10px;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .section-title {
    font-size: 18px;
    font-weight: 700;
    color: #1A1A2E;
    flex: 1;
  }
  .items-badge {
    background: #FFF0E6;
    color: #FF8F00;
    font-size: 12px;
    font-weight: 600;
    padding: 4px 12px;
    border-radius: 20px;
  }

  /* Parcels list */
  .parcels-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .parcel-item {
    display: flex;
    align-items: center;
    gap: 16px;
    background: #FAF9FE;
    border: 1px solid #F1F0F6;
    border-radius: 18px;
    height: 80px;
    padding: 0 20px;
    transition: all 0.25s ease;
    cursor: pointer;
  }
  .parcel-item:hover {
    border-color: #6A1B9A;
    background: #F8F5FF;
    box-shadow: 0 2px 12px rgba(106,27,154,0.08);
    transform: translateX(4px);
  }

  .parcel-checkbox {
    flex-shrink: 0;
  }
  .checkbox-custom {
    width: 22px;
    height: 22px;
    border-radius: 6px;
    border: 2px solid #D1D5DB;
    transition: all 0.2s ease;
  }
  .checkbox-custom.checked {
    background: #6A1B9A;
    border-color: #6A1B9A;
    position: relative;
  }
  .checkbox-custom.checked::after {
    content: '';
    position: absolute;
    left: 6px;
    top: 2px;
    width: 6px;
    height: 10px;
    border: solid white;
    border-width: 0 2px 2px 0;
    transform: rotate(45deg);
  }

  .parcel-info {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .parcel-code {
    font-size: 13px;
    font-weight: 600;
    color: #1A1A2E;
  }
  .parcel-date-row {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .parcel-date {
    font-size: 12px;
    color: #64748B;
  }

  .parcel-value-area {
    display: flex;
    align-items: center;
    gap: 8px;
    flex-shrink: 0;
  }
  .parcel-value {
    font-size: 15px;
    font-weight: 700;
    color: #1A1A2E;
  }

  /* Bottom info card */
  .bottom-info-card {
    display: flex;
    align-items: flex-start;
    gap: 16px;
    background: #FCFAFF;
    border: 1px solid #EBE5F5;
    border-radius: 22px;
    padding: 20px 24px;
    margin-top: 28px;
  }
  .info-card-icon {
    width: 44px;
    height: 44px;
    background: #F0EBFF;
    border-radius: 12px;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }
  .info-card-text strong {
    font-size: 14px;
    color: #1A1A2E;
    display: block;
    margin-bottom: 4px;
  }
  .info-card-text p {
    font-size: 13px;
    color: #64748B;
    line-height: 1.5;
  }

  /* Right column */
  .body-right {
    flex: 3;
    padding: 32px 28px;
    background: #FAF7FF;
    display: flex;
    flex-direction: column;
  }

  .summary-card {
    display: flex;
    flex-direction: column;
    gap: 20px;
    position: sticky;
    top: 24px;
  }

  .summary-header {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .summary-icon-wrapper {
    width: 36px;
    height: 36px;
    background: #F0EBFF;
    border-radius: 10px;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .summary-title {
    font-size: 16px;
    font-weight: 700;
    color: #1A1A2E;
  }

  .summary-rows {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }
  .summary-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .summary-label {
    font-size: 13px;
    color: #64748B;
  }
  .summary-value {
    font-size: 15px;
    font-weight: 600;
    color: #1A1A2E;
  }
  .summary-value.muted {
    color: #94A3B8;
  }

  .summary-divider {
    height: 1px;
    background: #EBE5F5;
    margin: 4px 0;
  }

  .summary-total-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .total-label {
    font-size: 14px;
    font-weight: 600;
    color: #1A1A2E;
  }
  .total-value {
    font-size: 34px;
    font-weight: 700;
    color: #6A1B9A;
    letter-spacing: -0.02em;
  }

  .pay-button {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
    height: 58px;
    width: 100%;
    border: none;
    border-radius: 16px;
    background: linear-gradient(135deg, #6A1B9A 0%, #FF8F00 100%);
    color: #FFFFFF;
    font-size: 16px;
    font-weight: 700;
    cursor: pointer;
    transition: all 0.25s ease;
    position: relative;
    overflow: hidden;
  }
  .pay-button::before {
    content: '';
    position: absolute;
    inset: 0;
    background: linear-gradient(135deg, rgba(255,255,255,0.1) 0%, transparent 50%);
    transition: opacity 0.25s ease;
  }
  .pay-button:hover {
    transform: translateY(-2px);
    box-shadow: 0 8px 24px rgba(106,27,154,0.25);
  }
  .pay-button:hover::before {
    opacity: 0;
  }
  .pay-button:active {
    transform: translateY(0);
  }

  .secure-badge {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    font-size: 12px;
    color: #64748B;
    padding: 4px 0;
  }

  /* Footer */
  .footer-bar {
    width: 100%;
    text-align: center;
    padding: 24px;
    font-size: 12px;
    color: #94A3B8;
    z-index: 1;
    position: relative;
  }

  /* Responsive */
  @media (max-width: 768px) {
    .card-body {
      flex-direction: column;
    }
    .body-left {
      border-right: none;
      border-bottom: 1px solid #F1F0F6;
    }
    .card-header {
      height: auto;
      flex-direction: column;
      gap: 20px;
      padding: 24px 20px;
    }
    .header-right {
      width: 100%;
    }
    .glass-card-total {
      width: 100%;
    }
  }
`;

const styles: Record<string, React.CSSProperties> = {
  outerContainer: {
    width: "100%",
    height: "100%",
    overflow: "auto",
    background: "#F5F4F8",
    fontFamily: "'Inter', sans-serif",
  },
};

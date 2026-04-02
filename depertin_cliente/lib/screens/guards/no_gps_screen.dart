import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/location_service.dart';

const Color _laranja = Color(0xFFFF8F00);
const Color _roxo = Color(0xFF6A1B9A);

class NoGpsScreen extends StatefulWidget {
  const NoGpsScreen({super.key});

  @override
  State<NoGpsScreen> createState() => _NoGpsScreenState();
}

class _NoGpsScreenState extends State<NoGpsScreen>
    with TickerProviderStateMixin {
  late final AnimationController _bounceController;
  late final Animation<double> _bounceAnimation;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _bounceAnimation = Tween<double>(begin: -5, end: 5).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locationService = context.watch<LocationService>();
    final status = locationService.status;

    final config = _configParaStatus(status);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const Spacer(flex: 3),
                _buildIconeAnimado(),
                const SizedBox(height: 48),
                Text(
                  config.titulo,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                Text(
                  config.descricao,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey[600],
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 44),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () => config.acaoPrincipal(locationService),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _laranja,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      config.textoBotaoPrincipal,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (config.textoSecundario != null) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton(
                      onPressed: () => locationService.verificarTudo(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4B5563),
                        side: const BorderSide(color: Color(0xFFD1D5DB)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        config.textoSecundario!,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
                const Spacer(flex: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text(
                    'DiPertin',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[350],
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconeAnimado() {
    return SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 120 + (60 * _pulseAnimation.value),
                height: 120 + (60 * _pulseAnimation.value),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _roxo.withValues(
                      alpha: 0.08 * (1 - _pulseAnimation.value)),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 120 + (30 * _pulseAnimation.value),
                height: 120 + (30 * _pulseAnimation.value),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _roxo.withValues(
                      alpha: 0.05 * (1 - _pulseAnimation.value)),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _bounceAnimation,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _bounceAnimation.value),
                child: child,
              );
            },
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _roxo.withValues(alpha: 0.08),
              ),
              child: Icon(
                Icons.location_off_rounded,
                size: 52,
                color: _roxo.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  _StatusConfig _configParaStatus(LocationStatus status) {
    switch (status) {
      case LocationStatus.servicoDesativado:
        return _StatusConfig(
          titulo: 'Ative sua localização',
          descricao:
              'Para acessar lojas, produtos e conteúdos da\nsua cidade, é necessário manter o GPS ativado.',
          textoBotaoPrincipal: 'Ativar localização',
          acaoPrincipal: (svc) => svc.abrirConfiguracoesLocalizacao(),
          textoSecundario: 'Tentar novamente',
        );
      case LocationStatus.permissaoNegada:
        return _StatusConfig(
          titulo: 'Permissão de localização',
          descricao:
              'O DiPertin precisa da sua localização para\nexibir lojas e produtos da sua cidade.',
          textoBotaoPrincipal: 'Permitir localização',
          acaoPrincipal: (svc) => svc.solicitarPermissao(),
          textoSecundario: 'Tentar novamente',
        );
      case LocationStatus.permissaoNegadaPermanente:
        return _StatusConfig(
          titulo: 'Localização bloqueada',
          descricao:
              'A permissão de localização foi negada permanentemente.\nAcesse as configurações do sistema para habilitá-la.',
          textoBotaoPrincipal: 'Abrir configurações',
          acaoPrincipal: (svc) => svc.abrirConfiguracoes(),
          textoSecundario: 'Tentar novamente',
        );
      default:
        return _StatusConfig(
          titulo: 'Ative sua localização',
          descricao:
              'Para acessar lojas, produtos e conteúdos da\nsua cidade, é necessário manter o GPS ativado.',
          textoBotaoPrincipal: 'Tentar novamente',
          acaoPrincipal: (svc) => svc.verificarTudo(),
        );
    }
  }
}

class _StatusConfig {
  final String titulo;
  final String descricao;
  final String textoBotaoPrincipal;
  final void Function(LocationService) acaoPrincipal;
  final String? textoSecundario;

  _StatusConfig({
    required this.titulo,
    required this.descricao,
    required this.textoBotaoPrincipal,
    required this.acaoPrincipal,
    this.textoSecundario,
  });
}

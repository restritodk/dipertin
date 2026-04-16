// Galeria em tela cheia com zoom (pinça) e slide entre imagens.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

const Color _diPertinLaranja = Color(0xFFFF8F00);

/// Abre o visualizador elegante (fundo preto, contador, indicadores).
Future<void> abrirGaleriaProdutoAmpliada(
  BuildContext context, {
  required List<String> urls,
  required int initialIndex,
}) async {
  if (urls.isEmpty) return;
  final i = initialIndex.clamp(0, urls.length - 1);
  await Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      fullscreenDialog: true,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
          child: _ProductGaleriaAmpliadaPage(urls: urls, initialIndex: i),
        );
      },
    ),
  );
}

class _ProductGaleriaAmpliadaPage extends StatefulWidget {
  const _ProductGaleriaAmpliadaPage({
    required this.urls,
    required this.initialIndex,
  });

  final List<String> urls;
  final int initialIndex;

  @override
  State<_ProductGaleriaAmpliadaPage> createState() =>
      _ProductGaleriaAmpliadaPageState();
}

class _ProductGaleriaAmpliadaPageState
    extends State<_ProductGaleriaAmpliadaPage> {
  late final PageController _pageController;
  late int _indice;

  @override
  void initState() {
    super.initState();
    _indice = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final multi = widget.urls.length > 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            PhotoViewGallery.builder(
              scrollPhysics: const BouncingScrollPhysics(),
              pageController: _pageController,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _indice = i),
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              loadingBuilder: (context, event) {
                final v =
                    event?.expectedTotalBytes != null &&
                        event!.expectedTotalBytes! > 0
                    ? event.cumulativeBytesLoaded / event.expectedTotalBytes!
                    : null;
                return Center(
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: _diPertinLaranja,
                      value: v,
                    ),
                  ),
                );
              },
              builder: (context, index) {
                final url = widget.urls[index];
                return PhotoViewGalleryPageOptions(
                  imageProvider: NetworkImage(url),
                  initialScale: PhotoViewComputedScale.contained,
                  minScale: PhotoViewComputedScale.contained * 0.8,
                  maxScale: PhotoViewComputedScale.covered * 3.2,
                  filterQuality: FilterQuality.high,
                  basePosition: Alignment.center,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white.withValues(alpha: 0.35),
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Não foi possível carregar esta imagem',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 15,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            // Barra superior: gradiente + fechar + contador
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.72),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 12, 20),
                    child: Row(
                      children: [
                        Material(
                          color: Colors.white.withValues(alpha: 0.12),
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: IconButton(
                            tooltip: 'Fechar',
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 26,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                        if (multi) ...[
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Text(
                              '${_indice + 1} / ${widget.urls.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Indicadores inferiores (estilo galeria)
            if (multi)
              Positioned(
                left: 0,
                right: 0,
                bottom: bottom + 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.urls.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      width: i == _indice ? 22 : 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == _indice
                            ? _diPertinLaranja
                            : Colors.white.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

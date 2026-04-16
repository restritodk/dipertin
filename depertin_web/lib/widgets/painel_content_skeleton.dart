import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/painel_admin_theme.dart';

/// Placeholder animado (shimmer) enquanto o painel troca de seção.
class PainelContentSkeleton extends StatelessWidget {
  const PainelContentSkeleton({super.key});

  static const _base = Color(0xFFE2E8F0);
  static const _highlight = Color(0xFFF1F5F9);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PainelAdminTheme.fundoCanvas,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 40, 40, 36),
        child: Shimmer.fromColors(
          baseColor: _base,
          highlightColor: _highlight,
          period: const Duration(milliseconds: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bar(height: 12, width: 140, radius: 6),
              const SizedBox(height: 16),
              _bar(height: 32, width: 280, radius: 8),
              const SizedBox(height: 12),
              _bar(height: 16, width: 360, radius: 6),
              const SizedBox(height: 36),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _cardPlaceholder()),
                  const SizedBox(width: 18),
                  Expanded(child: _cardPlaceholder()),
                  const SizedBox(width: 18),
                  Expanded(child: _cardPlaceholder()),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _cardPlaceholder()),
                  const SizedBox(width: 18),
                  Expanded(child: _cardPlaceholder()),
                ],
              ),
              const SizedBox(height: 32),
              _bar(height: 18, width: 200, radius: 6),
              const SizedBox(height: 16),
              SizedBox(
                height: 220,
                width: double.infinity,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar({
    required double height,
    required double width,
    required double radius,
  }) {
    return Container(
      height: height,
      width: width == double.infinity ? null : width,
      constraints: width == double.infinity
          ? const BoxConstraints.expand()
          : null,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _cardPlaceholder() {
    return Container(
      height: 132,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bar(height: 6, width: 48, radius: 3),
            const SizedBox(height: 18),
            _bar(height: 22, width: 72, radius: 6),
            const Spacer(),
            _bar(height: 12, width: 100, radius: 6),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Skeleton shimmer liviano (sin paquetes).
///
/// Úsalo para estados de carga en listas/cards, en vez de spinners.
class AppShimmer extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final Duration period;

  const AppShimmer({
    super.key,
    required this.child,
    this.enabled = true,
    this.period = const Duration(milliseconds: 1200),
  });

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.period);
    if (widget.enabled) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant AppShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = cs.surfaceContainerHighest.withOpacity(isDark ? 0.38 : 0.55);
    final hi = cs.onSurface.withOpacity(isDark ? 0.10 : 0.12);

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        // Desplazar gradiente de izquierda a derecha.
        final dx = (t * 2.0) - 1.0;
        return ShaderMask(
          shaderCallback: (rect) {
            return LinearGradient(
              begin: Alignment(-1.0 - dx, 0),
              end: Alignment(1.0 - dx, 0),
              colors: [base, hi, base],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(rect);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class AppSkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  const AppSkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppShimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(isDark ? 0.35 : 0.55),
          borderRadius: borderRadius,
        ),
      ),
    );
  }
}

/// Placeholder “tipo card de lista” para cargas.
class AppSkeletonListTile extends StatelessWidget {
  final bool dense;

  const AppSkeletonListTile({super.key, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final h = dense ? 66.0 : 78.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: SizedBox(
        height: h,
        child: Row(
          children: [
            const AppSkeletonBox(width: 54, height: 54, borderRadius: BorderRadius.all(Radius.circular(12))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  AppSkeletonBox(height: 14, borderRadius: BorderRadius.all(Radius.circular(10))),
                  SizedBox(height: 10),
                  FractionallySizedBox(
                    widthFactor: 0.72,
                    child: AppSkeletonBox(height: 12, borderRadius: BorderRadius.all(Radius.circular(10))),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid skeleton simple para pantallas en modo grid.
class AppSkeletonGridTile extends StatelessWidget {
  const AppSkeletonGridTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        Expanded(
          child: AppSkeletonBox(borderRadius: BorderRadius.all(Radius.circular(14))),
        ),
        SizedBox(height: 10),
        AppSkeletonBox(height: 12, borderRadius: BorderRadius.all(Radius.circular(10))),
        SizedBox(height: 8),
        FractionallySizedBox(
          widthFactor: 0.68,
          child: AppSkeletonBox(height: 11, borderRadius: BorderRadius.all(Radius.circular(10))),
        ),
        SizedBox(height: 8),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../app_logo.dart';
import '../../l10n/app_strings.dart';

/// Header/Dashboard principal de la Home.
///
/// Objetivo: que se sienta como una app premium (limpia, moderna, con jerarquía visual).
/// Mantiene la misma lógica (solo UI) vía callbacks.
class HomeHeader extends StatelessWidget {
  final int allCount;
  final int favoritesCount;
  final int wishlistCount;

  final VoidCallback onRefresh;
  final VoidCallback onVinyls;
  final VoidCallback onFavorites;
  final VoidCallback onWishlist;
  final VoidCallback onSearch;
  final VoidCallback onSoundtracks;
  final VoidCallback onScanner;
  final VoidCallback onSettings;
  final VoidCallback onTrash;

  const HomeHeader({
    super.key,
    required this.allCount,
    required this.favoritesCount,
    required this.wishlistCount,
    required this.onRefresh,
    required this.onVinyls,
    required this.onFavorites,
    required this.onWishlist,
    required this.onSearch,
    required this.onSoundtracks,
    required this.onScanner,
    required this.onSettings,
    required this.onTrash,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    final border = cs.outline.withOpacity(isDark ? 0.80 : 1.0);
    final soft = isDark ? 0.12 : 0.18;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: border),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    Color.lerp(cs.surface, cs.primaryContainer, 0.08) ?? cs.surface,
                    Color.lerp(cs.surfaceContainerHighest, cs.primaryContainer, 0.14) ?? cs.surfaceContainerHighest,
                  ]
                : [
                    Color.lerp(cs.surface, cs.primaryContainer, 0.22) ?? cs.surface,
                    Color.lerp(cs.surfaceContainerHighest, cs.primaryContainer, 0.10) ?? cs.surfaceContainerHighest,
                  ],
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: 28,
              spreadRadius: -6,
              offset: const Offset(0, 18),
              color: cs.shadow.withOpacity(soft),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Decoración sutil (círculos) para dar sensación premium.
            Positioned(
              right: -110,
              top: -80,
              child: _SoftOrb(size: 220, color: cs.primary.withOpacity(isDark ? 0.22 : 0.16)),
            ),
            Positioned(
              left: -140,
              bottom: -160,
              child: _SoftOrb(size: 320, color: cs.tertiary.withOpacity(isDark ? 0.18 : 0.12)),
            ),
            // “Surcos” estilo vinilo (retro). Muy sutil para no recargar.
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: isDark ? 0.10 : 0.08,
                  child: const _VinylGrooves(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Logo con “marco” para que resalte sobre cualquier tema.
                      Container(
                        // ✅ Pedido: el "card" del logo más pequeño, pero manteniendo el logo grande.
                        // Menos padding alrededor = marco más compacto y se ve más pro.
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: cs.surface.withOpacity(isDark ? 0.75 : 0.95),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: border),
                        ),
                        child: AppLogo(size: kHomeHeaderLogoSize),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Evitar cortes raros (“Tu estanterí…”) en pantallas
                            // estrechas: si falta espacio, el texto se escala
                            // hacia abajo (en vez de truncarse a 3 letras).
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                context.tr('Tu estantería'),
                                maxLines: 1,
                                style: t.textTheme.titleSmall?.copyWith(
                                  color: cs.onSurface.withOpacity(0.90),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _IconPill(
                        icon: Icons.refresh,
                        tooltip: context.tr('Actualizar'),
                        onTap: onRefresh,
                      ),
                    ],
                  ),

                  // Bajamos el slogan para que tenga ancho completo y no se recorte
                  // en pantallas más estrechas.
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      context.tr('Organiza tu música'),
                      maxLines: 2,
                      style: t.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withOpacity(0.72),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Stats (una sola línea)
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.library_music,
                          label: context.tr('Vinilos'),
                          value: allCount,
                          onTap: onVinyls,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.star,
                          label: context.tr('Favoritos'),
                          value: favoritesCount,
                          onTap: onFavorites,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.shopping_cart,
                          label: context.tr('Deseos'),
                          value: wishlistCount,
                          onTap: onWishlist,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // 🔍 Acceso directo: Discografías / Soundtrack (cada uno clickeable)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: cs.surface.withOpacity(isDark ? 0.68 : 0.92),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.search, size: 20, color: cs.onSurface.withOpacity(0.88)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _HomeQuickChip(
                                  icon: Icons.library_music_outlined,
                                  label: context.tr('Discos'),
                                  onTap: onSearch,
                                ),
                                const SizedBox(width: 8),
                                _HomeQuickChip(
                                  icon: Icons.local_movies_outlined,
                                  label: context.tr('OST'),
                                  onTap: onSoundtracks,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.touch_app, size: 18, color: cs.onSurface.withOpacity(0.55)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Acciones rápidas (responsive)
                  // - En pantallas angostas se vuelve 1 columna para que *siempre* se lea el texto.
                  LayoutBuilder(
                    builder: (context, c) {
                      final oneColumn = c.maxWidth < 430;
                      final crossAxis = oneColumn ? 1 : 2;
                      final items = <_ActionSpec>[
                        _ActionSpec(
                          icon: Icons.qr_code_scanner,
                          // ZWSP para permitir salto en palabras largas si hiciera falta.
                          title: context.tr('Escanear'),
                          subtitle: context.tr('Código de barras'),
                          onTap: onScanner,
                        ),
                        _ActionSpec(
                          icon: Icons.delete_outline,
                          title: context.tr('Borrar'),
                          subtitle: context.tr('Papelera y limpieza'),
                          onTap: onTrash,
                        ),
                        _ActionSpec(
                          icon: Icons.settings,
                          title: context.tr('Ajustes'),
                          subtitle: context.tr('Backup y diseño'),
                          onTap: onSettings,
                        ),
                      ];

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxis,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          // Más alto en 1 columna para que se lea cómodo.
                          childAspectRatio: oneColumn ? 4.2 : 2.25,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final it = items[i];
                          return _ActionTile(
                            icon: it.icon,
                            title: it.title,
                            subtitle: it.subtitle,
                            onTap: it.onTap,
                            compact: !oneColumn,
                          );
                        },
                      );
                    },
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

class _HomeQuickChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HomeQuickChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    final border = cs.outline.withOpacity(isDark ? 0.80 : 1.0);

    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(isDark ? 0.55 : 0.85),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: cs.onSurface.withOpacity(0.86)),
                const SizedBox(width: 6),
                Text(
                  label,
                  maxLines: 1,
                  style: t.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.85),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



class _IconPill extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconPill({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(isDark ? 0.72 : 0.95),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: cs.outline.withOpacity(isDark ? 0.75 : 1.0)),
            ),
            child: Icon(icon, color: cs.onSurface),
          ),
        ),
      ),
    );
  }
}

/// Ícono con look “label de vinilo”: sirve para stats y accesos.
class _BadgeIcon extends StatelessWidget {
  final IconData icon;
  const _BadgeIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    final rim = cs.onSurface.withOpacity(isDark ? 0.18 : 0.10);
    final groove = cs.onSurface.withOpacity(isDark ? 0.10 : 0.06);
    final label = cs.primary.withOpacity(isDark ? 0.65 : 0.55);

    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // disco
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.2, -0.2),
                colors: [
                  cs.surface.withOpacity(isDark ? 0.92 : 0.96),
                  cs.surfaceContainerHighest.withOpacity(isDark ? 0.86 : 0.90),
                ],
              ),
              border: Border.all(color: rim),
            ),
          ),
          // grooves
          ...List.generate(3, (i) {
            final pad = 6.0 + i * 5.0;
            return Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(pad),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: groove),
                  ),
                ),
              ),
            );
          }),
          // label centro
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: label,
              border: Border.all(color: rim),
            ),
          ),
          Icon(icon, size: 22, color: cs.onSurface),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final VoidCallback onTap;
  const _StatCard({required this.icon, required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    final border = cs.outline.withOpacity(isDark ? 0.75 : 1.0);
    final bg = cs.surface.withOpacity(isDark ? 0.70 : 0.92);

    // ✅ Stats: Layout vertical (label arriba, icono centro, número abajo).
    // Esto evita overflows cuando el número pasa de 99 a 100+ sin alterar el valor real.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Label arriba
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: t.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: cs.onSurface.withOpacity(0.82),
                  ),
                ),
              ),
            ),

            // Icono centro
            Center(child: _BadgeIcon(icon: icon)),

            // Número abajo (valor real)
            Center(
              child: Text(
                value.toString(),
                maxLines: 1,
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: t.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                    fontSize: 13,
                  letterSpacing: -0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool compact;
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;
    final border = cs.outline.withOpacity(isDark ? 0.75 : 1.0);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: border),
          color: cs.surface.withOpacity(isDark ? 0.70 : 0.92),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _BadgeIcon(icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900,
                    fontSize: 13, letterSpacing: -0.2),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.78),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurface.withOpacity(0.55)),
          ],
        ),
      ),
    );
  }
}

class _ActionSpec {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  _ActionSpec({required this.icon, required this.title, required this.subtitle, required this.onTap});
}

class _VinylGrooves extends StatelessWidget {
  const _VinylGrooves();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GroovePainter(color: Theme.of(context).colorScheme.onSurface),
    );
  }
}

class _GroovePainter extends CustomPainter {
  final Color color;
  const _GroovePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color.withOpacity(0.22);

    // Centro aproximado del “disco” hacia el lado derecho.
    final center = Offset(size.width * 0.86, size.height * 0.20);
    final maxR = size.shortestSide * 0.70;
    for (var i = 0; i < 6; i++) {
      final r = maxR * (0.18 + i * 0.10);
      canvas.drawCircle(center, r, p);
    }
  }

  @override
  bool shouldRepaint(covariant _GroovePainter oldDelegate) => oldDelegate.color != color;
}

class _SoftOrb extends StatelessWidget {
  final double size;
  final Color color;
  const _SoftOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color,
            color.withOpacity(0.0),
          ],
        ),
      ),
    );
  }
}

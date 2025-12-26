import 'package:flutter/material.dart';

import '../app_logo.dart';

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
  final VoidCallback onScanner;
  final VoidCallback onDiscography;
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
    required this.onScanner,
    required this.onDiscography,
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
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.surface.withOpacity(isDark ? 0.75 : 0.95),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: border),
                        ),
                        child: const AppLogo(size: kHomeHeaderLogoSize),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ahora sonando',
                              style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.4),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Tu estantería • vinilo a vinilo',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.72),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _IconPill(
                        icon: Icons.refresh,
                        tooltip: 'Actualizar',
                        onTap: onRefresh,
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Stats (una sola línea)
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.library_music,
                          label: 'Vinilos',
                          value: allCount,
                          onTap: onVinyls,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.star,
                          label: 'Favoritos',
                          value: favoritesCount,
                          onTap: onFavorites,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.shopping_cart,
                          label: 'Deseos',
                          value: wishlistCount,
                          onTap: onWishlist,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // “Search bar” (tap to open)
                  InkWell(
                    onTap: onSearch,
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: cs.surface.withOpacity(isDark ? 0.68 : 0.92),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 20, color: cs.onSurface.withOpacity(0.88)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Buscar artista o álbum…',
                              style: t.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurface.withOpacity(0.70),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Icon(Icons.keyboard_arrow_right, color: cs.onSurface.withOpacity(0.55)),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Acciones rápidas (grid 2x2)
                  Row(
                    children: [
                      Expanded(
                        child: _ActionTile(
                          icon: Icons.qr_code_scanner,
                          title: 'Escanear',
                          subtitle: 'Código de barras',
                          onTap: onScanner,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionTile(
                          icon: Icons.library_music,
                          title: 'Discografías',
                          subtitle: 'Busca por artista',
                          onTap: onDiscography,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionTile(
                          icon: Icons.delete_outline,
                          title: 'Borrar',
                          subtitle: 'Papelera y limpieza',
                          onTap: onTrash,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionTile(
                          icon: Icons.settings,
                          title: 'Ajustes',
                          subtitle: 'Backup y diseño',
                          onTap: onSettings,
                        ),
                      ),
                    ],
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

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: cs.primary.withOpacity(isDark ? 0.22 : 0.14),
                border: Border.all(color: cs.primary.withOpacity(isDark ? 0.34 : 0.22)),
              ),
              child: Icon(icon, color: cs.onSurface),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AnimatedCount(value: value),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.labelMedium?.copyWith(
                      color: cs.onSurface.withOpacity(0.75),
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
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

class _AnimatedCount extends StatelessWidget {
  final int value;
  const _AnimatedCount({required this.value});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final style = t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.8);
    return Text('$value', style: style);
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

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
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.primary.withOpacity(isDark ? 0.28 : 0.18),
                    cs.tertiary.withOpacity(isDark ? 0.22 : 0.14),
                  ],
                ),
                border: Border.all(color: cs.primary.withOpacity(isDark ? 0.34 : 0.22)),
              ),
              child: Icon(icon, color: cs.onSurface),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.3),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.70),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurface.withOpacity(0.50)),
          ],
        ),
      ),
    );
  }
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

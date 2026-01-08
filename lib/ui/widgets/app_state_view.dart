import 'package:flutter/material.dart';

/// Vista unificada para estados: vacío / error.
///
/// Mantiene la app con un look profesional y consistente.
class AppStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionText;
  final VoidCallback? onAction;

  const AppStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionText,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;
    final border = cs.outlineVariant.withOpacity(isDark ? 0.70 : 0.45);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(isDark ? 0.75 : 0.95),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.surfaceContainerHighest.withOpacity(isDark ? 0.55 : 0.70),
                    border: Border.all(color: border),
                  ),
                  child: Icon(icon, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (actionText != null && onAction != null) ...[
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: onAction,
                    child: Text(actionText!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

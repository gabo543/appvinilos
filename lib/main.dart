import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'ui/home_screen.dart';
import 'services/app_theme_service.dart';
import 'services/view_mode_service.dart';
import 'services/locale_service.dart';
import 'l10n/app_strings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // ✅ Cargamos preferencias 1 vez para cambios instantáneos (tema + grid/list).
  await AppThemeService.load();
  await ViewModeService.load();
  await LocaleService.load();
  runApp(const GaBoLpApp());
}

class GaBoLpApp extends StatelessWidget {
  const GaBoLpApp({super.key});

  ThemeData _applyCardBorderStyle(ThemeData base, int style1to10) {
    // El usuario elige un color (1..10) para el contorno/borde.
    final c = AppThemeService.borderBaseColor(style1to10);
    final isDark = base.scaffoldBackgroundColor.computeLuminance() < 0.42;

    // Usamos el mismo color como "outline" y "outlineVariant" para que
    // todos los contornos que ya usan el ColorScheme se actualicen sin
    // tener que tocar cada widget.
    final cs = base.colorScheme;
    final newCs = cs.copyWith(
      outline: c,
      outlineVariant: c,
    );

    // CardTheme: mantenemos radio/ancho, solo cambiamos el color.
    final card = base.cardTheme;
    final shape = card.shape;

    RoundedRectangleBorder rrb;
    if (shape is RoundedRectangleBorder) {
      rrb = shape;
    } else {
      rrb = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(width: 1),
      );
    }

    final side = rrb.side;
    final resolved = c.withOpacity(isDark ? 0.90 : 0.70);
    final newShape = RoundedRectangleBorder(
      borderRadius: rrb.borderRadius,
      side: side.copyWith(color: resolved),
    );

    return base.copyWith(
      colorScheme: newCs,
      cardTheme: card.copyWith(shape: newShape),
      // Dividers suelen sentirse como "borde"; los alineamos con el contorno.
      dividerColor: resolved.withOpacity(isDark ? 0.65 : 0.50),
    );
  }
ThemeData _makeTheme({
  required Brightness brightness,
  required Color bg,
  required Color surface,
  required Color card,
  required Color accent,
  required Color onAccent,
  required Color outline,
  required Color variant,
  required Color onSurface,
  required Color onVariant,
  required Color shadow,
}) {
  // ⚠️ Compat Flutter 3.22+ (Material 3): `background`, `onBackground` y `surfaceVariant`
  // fueron deprecados y pueden estar removidos en releases nuevas.
  // Migración recomendada (Flutter breaking change docs):
  //   background → surface
  //   onBackground → onSurface
  //   surfaceVariant → surfaceContainerHighest
  // Por eso evitamos usar esos campos aquí.
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness).copyWith(
    primary: accent,
    onPrimary: onAccent,
    secondary: accent,
    onSecondary: onAccent,
    // background/onBackground removidos en versiones nuevas: usamos scaffoldBackgroundColor + onSurface.
    surface: surface,
    onSurface: onSurface,
    surfaceContainerHighest: variant,
    onSurfaceVariant: onVariant,
    outline: outline,
    outlineVariant: outline,
    shadow: shadow,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: bg,
  );

  final isDark = brightness == Brightness.dark;

  final textTheme = base.textTheme
      .apply(bodyColor: onSurface, displayColor: onSurface)
      .copyWith(
        headlineSmall: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2),
        titleLarge: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2),
        titleMedium: const TextStyle(fontWeight: FontWeight.w800),
        bodyLarge: const TextStyle(fontWeight: FontWeight.w600),
        bodyMedium: const TextStyle(fontWeight: FontWeight.w500),
        bodySmall: const TextStyle(fontWeight: FontWeight.w600),
        labelLarge: const TextStyle(fontWeight: FontWeight.w800),
      );

  final border = outline.withOpacity(isDark ? 0.70 : 0.55);

  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: onSurface,
      elevation: 0,
      centerTitle: false,
      scrolledUnderElevation: 0,
      surfaceTintColor: bg,
    ),
    iconTheme: IconThemeData(color: onSurface),
    dividerColor: border.withOpacity(isDark ? 0.55 : 0.60),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      shadowColor: shadow.withOpacity(0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border, width: 0.8),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: onSurface.withOpacity(0.92),
      textColor: onSurface,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: variant,
      labelStyle: TextStyle(color: onSurface, fontWeight: FontWeight.w700),
      secondaryLabelStyle: TextStyle(color: onSurface, fontWeight: FontWeight.w700),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      shape: StadiumBorder(side: BorderSide(color: outline.withOpacity(isDark ? 0.75 : 0.65))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: variant,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline.withOpacity(isDark ? 0.70 : 0.65)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline.withOpacity(isDark ? 0.55 : 0.55)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accent.withOpacity(0.95), width: 1.4),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: card,
      contentTextStyle: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
    ),
    dialogTheme: base.dialogTheme.copyWith(backgroundColor: card),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      modalBackgroundColor: card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: onSurface,
        side: BorderSide(color: outline.withOpacity(isDark ? 0.75 : 0.70)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}


  ThemeData _theme1() {
  // 🎨 Obsidiana (Oscuro premium)
  return _makeTheme(
    brightness: Brightness.dark,
    bg: const Color(0xFF0B0B0B),
    surface: const Color(0xFF121318),
    card: const Color(0xFF151820),
    accent: const Color(0xFFA9D3FF),
    onAccent: const Color(0xFF0A0A0A),
    outline: const Color(0xFF2A2C32),
    variant: const Color(0xFF1B1D22),
    onSurface: const Color(0xFFF3F4F6),
    onVariant: const Color(0xFFB8C1CC),
    shadow: const Color(0xFF000000),
  );
}


  // ✅ Diseño 2 (B3): Claro premium.
  ThemeData _theme2() {
  // 🎨 Marfil (Claro premium)
  return _makeTheme(
    brightness: Brightness.light,
    bg: const Color(0xFFFAF8F4),
    surface: const Color(0xFFFFFFFF),
    card: const Color(0xFFFFFFFF),
    accent: const Color(0xFF2D4BFF),
    onAccent: const Color(0xFFFFFFFF),
    outline: const Color(0xFFE2DDD4),
    variant: const Color(0xFFF3EEE7),
    onSurface: const Color(0xFF141414),
    onVariant: const Color(0xFF5A5A5A),
    shadow: const Color(0xFF000000),
  );
}


  // ✅ Diseño 3 (B1): Minimal oscuro ultra limpio (diferente al Diseño 1).
  ThemeData _theme3() {
  // 🎨 Grafito (Oscuro mate)
  return _makeTheme(
    brightness: Brightness.dark,
    bg: const Color(0xFF111316),
    surface: const Color(0xFF15181C),
    card: const Color(0xFF181C21),
    accent: const Color(0xFF9FE7C9),
    onAccent: const Color(0xFF0D1211),
    outline: const Color(0xFF2B3137),
    variant: const Color(0xFF1D232A),
    onSurface: const Color(0xFFE9EEF3),
    onVariant: const Color(0xFFB0BAC6),
    shadow: const Color(0xFF000000),
  );
}



  ThemeData _theme4() {
  // 🎨 Vinilo Retro (sleeve oscuro + acento cálido)
  return _makeTheme(
    brightness: Brightness.dark,
    bg: const Color(0xFF0F0B08),        // fondo tipo "sala"
    surface: const Color(0xFF17110D),   // superficie cuero/papel
    card: const Color(0xFF1E1611),      // cards
    accent: const Color(0xFFD45A2A),    // naranja quemado (label)
    onAccent: const Color(0xFFFFF4E8),  // crema
    outline: const Color(0xFF3F2C22),   // borde cálido
    variant: const Color(0xFF241A14),   // inputs/chips
    onSurface: const Color(0xFFF6EDE3), // texto
    onVariant: const Color(0xFFCAB9AA),
    shadow: const Color(0xFF000000),
  );
}
ThemeData _theme5() {
  // 🎨 Lila Soft
  return _makeTheme(
    brightness: Brightness.dark,
    bg: const Color(0xFF110E15),
    surface: const Color(0xFF17131F),
    card: const Color(0xFF1B1626),
    accent: const Color(0xFFC7A6FF),
    onAccent: const Color(0xFF140A1F),
    outline: const Color(0xFF362B4E),
    variant: const Color(0xFF201A2C),
    onSurface: const Color(0xFFF3ECFF),
    onVariant: const Color(0xFFC7BCD8),
    shadow: const Color(0xFF000000),
  );
}


  ThemeData _theme6() {
  // 🎨 Verde Sala (Hi‑Fi)
  return _makeTheme(
    brightness: Brightness.dark,
    bg: const Color(0xFF0D1412),
    surface: const Color(0xFF131B17),
    card: const Color(0xFF15201B),
    accent: const Color(0xFFB8D8A8),
    onAccent: const Color(0xFF0E1510),
    outline: const Color(0xFF2A3A31),
    variant: const Color(0xFF1A2821),
    onSurface: const Color(0xFFE7F3EC),
    onVariant: const Color(0xFFB4C8BD),
    shadow: const Color(0xFF000000),
  );
}


  
  ThemeData _applyProSystem(ThemeData base) {
    // ✅ Sistema visual global: tipografía + jerarquía + componentes.
    final cs = base.colorScheme;

    TextStyle _t(TextStyle? s) => s ?? const TextStyle();

    // Tipografía: más contraste visual por tamaños/pesos (sin romper layouts).
    final tt = base.textTheme;
    final proTextTheme = tt.copyWith(
      displaySmall: _t(tt.displaySmall).copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.8,
        height: 1.05,
      ),
      headlineMedium: _t(tt.headlineMedium).copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.6,
        height: 1.10,
      ),
      headlineSmall: _t(tt.headlineSmall).copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.4,
        height: 1.12,
      ),
      titleLarge: _t(tt.titleLarge).copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
        height: 1.15,
      ),
      titleMedium: _t(tt.titleMedium).copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        height: 1.18,
      ),
      titleSmall: _t(tt.titleSmall).copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.18,
      ),
      bodyLarge: _t(tt.bodyLarge).copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.28,
      ),
      bodyMedium: _t(tt.bodyMedium).copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.30,
      ),
      bodySmall: _t(tt.bodySmall).copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.30,
      ),
      labelLarge: _t(tt.labelLarge).copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
      labelMedium: _t(tt.labelMedium).copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      labelSmall: _t(tt.labelSmall).copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );

    final isDark = base.brightness == Brightness.dark;
    final surfaceFill = isDark ? cs.surface.withOpacity(0.65) : cs.surface;

    return base.copyWith(
      textTheme: proTextTheme,
      primaryTextTheme: base.primaryTextTheme.merge(proTextTheme),
      appBarTheme: base.appBarTheme.copyWith(
        toolbarHeight: 60,
        // ✅ Tamaño único para títulos en toda la app (Vinilos/Favoritos/Deseos/...)
        // Evita que “Vinilos” se vea más chico cuando hay muchas acciones.
        titleTextStyle: proTextTheme.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: cs.onSurface,
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        elevation: base.cardTheme.elevation ?? 1.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        horizontalTitleGap: 12,
        minLeadingWidth: 28,
        iconColor: cs.onSurface,
        titleTextStyle: proTextTheme.titleMedium?.copyWith(color: cs.onSurface),
        subtitleTextStyle: proTextTheme.bodyMedium?.copyWith(
          color: cs.onSurface.withOpacity(0.75),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        labelStyle: proTextTheme.labelMedium?.copyWith(color: cs.onSurface),
        side: BorderSide(color: cs.outline.withOpacity(0.7)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      dividerTheme: base.dividerTheme.copyWith(
        color: cs.outline.withOpacity(isDark ? 0.55 : 0.35),
        thickness: 1,
        space: 1,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        titleTextStyle: proTextTheme.headlineSmall?.copyWith(color: cs.onSurface),
        contentTextStyle: proTextTheme.bodyMedium?.copyWith(color: cs.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: surfaceFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.outline.withOpacity(0.7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.outline.withOpacity(0.7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.primary.withOpacity(0.9), width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      textSelectionTheme: base.textSelectionTheme.copyWith(
        cursorColor: cs.primary,
        selectionColor: cs.primary.withOpacity(0.25),
        selectionHandleColor: cs.primary,
      ),
    );
  }

ThemeData _applyTextIntensity(ThemeData base, int level) {
    // level: 1..10 (más niveles = más contraste)
    // ✅ No dependemos solo de ThemeData.brightness, porque el usuario puede
    // cambiar el fondo (1..10) hacia claro/oscuro. Usamos luminancia real.
    final bg = base.scaffoldBackgroundColor;
    final isDark = bg.computeLuminance() < 0.42;
    final idx = level.clamp(1, 10);
    final tRaw = (idx - 1) / 9.0; // 0..1
    final t = Curves.easeOutCubic.transform(tRaw);

    // Fondo oscuro: desde gris a blanco
    // Fondo claro: desde gris oscuro a negro
    final Color c = isDark
        ? Color.lerp(const Color(0xFFB8B8B8), Colors.white, t)!
        : Color.lerp(const Color(0xFF2E2E2E), Colors.black, t)!;

    final textTheme = base.textTheme.apply(bodyColor: c, displayColor: c);
    final primaryTextTheme = base.primaryTextTheme.apply(bodyColor: c, displayColor: c);

    final cs = base.colorScheme;
    final newCs = cs.copyWith(
      onSurface: c,
      onSecondaryContainer: c,
      onPrimaryContainer: c,
    );

    return base.copyWith(
      colorScheme: newCs,
      textTheme: textTheme,
      primaryTextTheme: primaryTextTheme,
    );
  }

  ThemeData _applyBackgroundLevel(ThemeData base, int level) {
  // level: 1..10 (más alto = más oscuro)
  final idx = level.clamp(1, 10);
  final tRaw = (idx - 1) / 9.0;
  final t = Curves.easeOutCubic.transform(tRaw);

  Color shiftLightness(Color c, double delta) {
    final hsl = HSLColor.fromColor(c);
    final l = (hsl.lightness + delta).clamp(0.04, 0.96);
    return hsl.withLightness(l).toColor();
  }

  final baseBg = base.scaffoldBackgroundColor;
  final lightBg = shiftLightness(baseBg, 0.14);
  final darkBg = shiftLightness(baseBg, -0.22);
  final bg = Color.lerp(lightBg, darkBg, t) ?? baseBg;

  final isDark = bg.computeLuminance() < 0.42;
  final card = shiftLightness(bg, isDark ? 0.06 : -0.04);
  final variant = shiftLightness(bg, isDark ? 0.10 : -0.06);

  final cs = base.colorScheme;
  final newCs = cs.copyWith(
    // background removido: el fondo real se controla con scaffoldBackgroundColor.
    surface: card,
    surfaceContainerHighest: variant,
  );

  return base.copyWith(
    scaffoldBackgroundColor: bg,
    colorScheme: newCs,
    appBarTheme: base.appBarTheme.copyWith(backgroundColor: bg, surfaceTintColor: bg),
    cardTheme: base.cardTheme.copyWith(color: card),
    dialogTheme: base.dialogTheme.copyWith(backgroundColor: card),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: card,
      modalBackgroundColor: card,
    ),
    chipTheme: base.chipTheme.copyWith(backgroundColor: variant),
  );
}


  ThemeData _applyCardLevel(ThemeData base, int level) {
    // level: 1..10
    final idx = level.clamp(1, 10);
    final isDark = base.scaffoldBackgroundColor.computeLuminance() < 0.42;

    final tRaw = (idx - 1) / 9.0;
    final t = Curves.easeOutCubic.transform(tRaw);

    final elev = (t * 14.0);
    final radius = 12.0 + (t * 14.0);
    final borderColor = isDark
        ? Color.lerp(base.colorScheme.outline, Colors.white.withOpacity(0.45), t)!
        : Color.lerp(base.colorScheme.outline, Colors.black.withOpacity(0.25), t)!;

    final card = base.cardTheme;
    return base.copyWith(
      cardTheme: card.copyWith(
        elevation: elev,
        shadowColor: base.colorScheme.shadow.withOpacity(0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: borderColor, width: 0.6 + (t * 1.0)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppThemeService.themeNotifier,
      builder: (_, themeId, __) {
        return ValueListenableBuilder<int>(
          valueListenable: AppThemeService.textIntensityNotifier,
          builder: (_, intensity, __) {
            return ValueListenableBuilder<int>(
              valueListenable: AppThemeService.bgLevelNotifier,
              builder: (_, bgLevel, __) {
                return ValueListenableBuilder<int>(
                  valueListenable: AppThemeService.cardLevelNotifier,
                  builder: (_, cardLevel, __) {
                    return ValueListenableBuilder<int>(
                      valueListenable: AppThemeService.cardBorderStyleNotifier,
                      builder: (_, borderStyle, __) {
                        ThemeData base = switch (themeId) {
                          2 => _theme2(),
                          3 => _theme3(),
                          4 => _theme4(),
                          5 => _theme5(),
                          6 => _theme6(),
                          _ => _theme1(),
                        };

                        base = _applyProSystem(base);

                        // ✅ Orden: primero paleta de fondo/superficies, luego contraste de texto.
                        ThemeData theme = _applyBackgroundLevel(base, bgLevel);
                        theme = _applyTextIntensity(theme, intensity);
                        theme = _applyCardLevel(theme, cardLevel);
                        theme = _applyCardBorderStyle(theme, borderStyle);

                                                                                                                                                return ValueListenableBuilder<Locale>(
                          valueListenable: LocaleService.localeNotifier,
                          builder: (_, locale, __) {
                            return MaterialApp(
                              debugShowCheckedModeBanner: false,
                              locale: locale,
                              supportedLocales: const [Locale('es'), Locale('en')],
                              localizationsDelegates: const [
                                GlobalMaterialLocalizations.delegate,
                                GlobalWidgetsLocalizations.delegate,
                                GlobalCupertinoLocalizations.delegate,
                              ],
                              title: AppStrings.tRaw('Colección vinilos'),
                              theme: theme,
                              home: HomeScreen(),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

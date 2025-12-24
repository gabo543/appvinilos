import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ui/home_screen.dart';
import 'services/app_theme_service.dart';
import 'services/view_mode_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // ✅ Cargamos preferencias 1 vez para cambios instantáneos (tema + grid/list).
  await AppThemeService.load();
  await ViewModeService.load();
  runApp(const GaBoLpApp());
}

class GaBoLpApp extends StatelessWidget {
  const GaBoLpApp({super.key});

  ThemeData _theme1() {
    // ✅ Solo UI: tema oscuro "premium" (negro/gris) sin tocar lógica.
    const seed = Color(0xFF8E8E8E);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xFF141414),
      onSurface: const Color(0xFFEDEDED),
      primary: const Color(0xFFEDEDED),
      onPrimary: const Color(0xFF0F0F0F),
      secondary: const Color(0xFFA7A7A7),
      onSecondary: const Color(0xFF0F0F0F),
      outline: const Color(0xFF2B2B2B),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0F0F0F),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F0F0F),
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
      ),
      // ThemeData.cardTheme usa CardThemeData (Flutter 3.27+ / theme normalization).
      cardTheme: CardThemeData(
        // ✅ En tema oscuro, las cards NO pueden ser blancas porque el texto/iconos
        // del ListTile están pensados para fondo oscuro.
        color: scheme.surface,
        elevation: 2,
        shadowColor: const Color(0x22000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(26)),
          side: BorderSide(color: scheme.outline),
        ),
        margin: EdgeInsets.symmetric(vertical: 10),
      ),
            textTheme: ThemeData(
              useMaterial3: true,
              colorScheme: scheme,
              brightness: Brightness.dark,
            )
                .textTheme
                .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
                .copyWith(
headlineSmall: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2),
        titleLarge: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2),
        titleMedium: const TextStyle(fontWeight: FontWeight.w800),
        bodyLarge: const TextStyle(fontWeight: FontWeight.w600),
        bodyMedium: const TextStyle(fontWeight: FontWeight.w500),
        labelLarge: const TextStyle(fontWeight: FontWeight.w800),
                ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1B1B1B),
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF141414),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFBDBDBD)),
        ),
        labelStyle: const TextStyle(color: Color(0xFFBDBDBD)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFF2A2A2A)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      iconTheme: const IconThemeData(color: Colors.white),

      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurface,
        textColor: scheme.onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF111111),
        selectedColor: const Color(0xFF1B1B1B),
        disabledColor: const Color(0xFF101010),
        labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        secondaryLabelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999), side: const BorderSide(color: Color(0xFF2A2A2A))),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFF141414),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18)), side: BorderSide(color: Color(0xFF242424))),
      ),
      dividerColor: const Color(0xFF242424),
    );
  }

  // ✅ Diseño 2 (B3): Claro premium.
  ThemeData _theme2() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF111111),
      brightness: Brightness.light,
    ).copyWith(
      surface: const Color(0xFFFFFFFF),
      onSurface: const Color(0xFF0F0F0F),
      primary: const Color(0xFF0F0F0F),
      onPrimary: const Color(0xFFFFFFFF),
      secondary: const Color(0xFF4A4A4A),
      onSecondary: const Color(0xFFFFFFFF),
      outline: const Color(0xFFE6E6E6),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF7F7F7),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF7F7F7),
        foregroundColor: Color(0xFF0F0F0F),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: Color(0xFFE6E6E6)),
        ),
        margin: EdgeInsets.symmetric(vertical: 6),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2, color: Color(0xFF0F0F0F)),
        titleLarge: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2, color: Color(0xFF0F0F0F)),
        titleMedium: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F0F0F)),
        bodyLarge: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F0F0F)),
        bodyMedium: TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF0F0F0F)),
        labelLarge: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F0F0F)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE6E6E6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF0F0F0F)),
        ),
        labelStyle: const TextStyle(color: Color(0xFF4A4A4A)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF0F0F0F),
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18)), side: BorderSide(color: Color(0xFFE6E6E6))),
      ),
      iconTheme: const IconThemeData(color: Color(0xFF0F0F0F)),
      dividerColor: const Color(0xFFE6E6E6),
    );
  }

  // ✅ Diseño 3 (B1): Minimal oscuro ultra limpio (diferente al Diseño 1).
  ThemeData _theme3() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00D1FF),
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xFF0B0B0B),
      onSurface: const Color(0xFFF2F2F2),
      primary: const Color(0xFFF2F2F2),
      onPrimary: const Color(0xFF0B0B0B),
      secondary: const Color(0xFF8A8A8A),
      onSecondary: const Color(0xFF0B0B0B),
      outline: const Color(0xFF1C1C1C),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF000000),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      // Minimal: tarjetas planas, esquinas más rectas y bordes finos.
      cardTheme: const CardThemeData(
        color: Color(0xFF050505),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          side: BorderSide(color: Color(0xFF1A1A1A)),
        ),
        margin: EdgeInsets.symmetric(vertical: 6),
      ),
            textTheme: ThemeData(
              useMaterial3: true,
              colorScheme: scheme,
              brightness: Brightness.dark,
            )
                .textTheme
                .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
                .copyWith(
headlineSmall: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2, fontSize: 20),
        titleLarge: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2, fontSize: 18),
        titleMedium: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        bodyLarge: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        bodyMedium: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        labelLarge: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0, fontSize: 12),
                ),
      iconTheme: const IconThemeData(color: Colors.white, size: 22),
      dividerColor: const Color(0xFF1A1A1A),
    );
  }


  ThemeData _theme4() {
    // Diseño 4: Pastel Citrus (BRONCE / NEGRO / ROJO) — premium.
    const bg = Color(0xFF070607); // negro
    const surf = Color(0xFF121014); // negro cálido
    const bronze = Color(0xFFB08D57); // bronce
    const bronze2 = Color(0xFFD1B27C); // bronce claro
    const red = Color(0xFFE53935); // rojo

    final cs = ColorScheme.fromSeed(
      seedColor: bronze,
      brightness: Brightness.dark,
    ).copyWith(
      background: bg,
      surface: surf,
      primary: bronze,
      onPrimary: const Color(0xFF0A0A0A),
      secondary: red,
      onSecondary: Colors.white,
      tertiary: bronze2,
      onTertiary: const Color(0xFF0A0A0A),
      onSurface: const Color(0xFFF3EBDD),
      onBackground: const Color(0xFFF3EBDD),
      outline: const Color(0xFF2B2420),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: cs,
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: surf,
        elevation: 1,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outline),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: cs.onSurface,
        textColor: cs.onSurface,
      ),
      iconTheme: IconThemeData(color: cs.onSurface, size: 22),
      dividerColor: cs.outline,
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF1A171B),
        selectedColor: bronze.withOpacity(0.22),
        labelStyle: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
        secondaryLabelStyle: TextStyle(color: cs.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(color: cs.outline),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: bronze,
          foregroundColor: const Color(0xFF0A0A0A),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurface,
          side: BorderSide(color: cs.outline),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: red,
        foregroundColor: Colors.white,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1A171B),
        contentTextStyle: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
        actionTextColor: bronze2,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF161318),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: bronze, width: 1.4),
        ),
        labelStyle: TextStyle(color: cs.onSurface.withOpacity(0.75)),
      ),
    );
  }

  ThemeData _theme5() {
    // Diseño 5: Pastel Sky (oscuro con acento lila/celeste)
    const bg = Color(0xFF0D0F14);
    const surf = Color(0xFF151A24);
    const accent = Color(0xFFB39DDB); // lila
    const accent2 = Color(0xFF80DEEA); // celeste

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: surf,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: surf,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Color(0xFF232A3A)),
        ),
      ),
      listTileTheme: const ListTileThemeData(iconColor: Colors.white, textColor: Colors.white),
      iconTheme: const IconThemeData(color: Colors.white, size: 22),
      dividerColor: const Color(0xFF232A3A),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF1A2030),
        selectedColor: accent2.withOpacity(0.18),
        labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFF2B3348)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent2,
        foregroundColor: Colors.black,
      ),
    );
  }

  ThemeData _theme6() {
    // Diseño 6: Rasta Vibes (verde/amarillo/rojo)
    const bg = Color(0xFF050505);
    const surf = Color(0xFF0C0F0B);
    const green = Color(0xFF1DB954); // verde vivo
    const yellow = Color(0xFFF6C343);
    const red = Color(0xFFE53935);

    final cs = ColorScheme.fromSeed(
      seedColor: green,
      brightness: Brightness.dark,
      surface: surf,
    ).copyWith(
      primary: green,
      secondary: yellow,
      tertiary: red,
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onTertiary: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: cs,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      dividerColor: const Color(0xFF1C1C1C),
      cardTheme: CardThemeData(
        color: surf,
        elevation: 1,
        shadowColor: Colors.black,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: yellow.withOpacity(0.22)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: Colors.white,
        textColor: Colors.white,
      ),
      iconTheme: const IconThemeData(color: Colors.white, size: 22),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF121212),
        selectedColor: green.withOpacity(0.18),
        labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        secondaryLabelStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(color: red.withOpacity(0.22)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: yellow.withOpacity(0.45)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: yellow,
        foregroundColor: Colors.black,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF101010),
        contentTextStyle: const TextStyle(color: Colors.white),
        actionTextColor: yellow,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0F0F0F),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: yellow.withOpacity(0.30))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: yellow.withOpacity(0.18))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: green, width: 1.4)),
      ),
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
        fontSize: 26,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.6,
        height: 1.10,
      ),
      headlineSmall: _t(tt.headlineSmall).copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.4,
        height: 1.12,
      ),
      titleLarge: _t(tt.titleLarge).copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
        height: 1.15,
      ),
      titleMedium: _t(tt.titleMedium).copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        height: 1.18,
      ),
      titleSmall: _t(tt.titleSmall).copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.18,
      ),
      bodyLarge: _t(tt.bodyLarge).copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.28,
      ),
      bodyMedium: _t(tt.bodyMedium).copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.30,
      ),
      bodySmall: _t(tt.bodySmall).copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.30,
      ),
      labelLarge: _t(tt.labelLarge).copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
      labelMedium: _t(tt.labelMedium).copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      labelSmall: _t(tt.labelSmall).copyWith(
        fontSize: 11,
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
        titleTextStyle: proTextTheme.titleLarge?.copyWith(
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
        ? Color.lerp(const Color(0xFF8E8E8E), Colors.white, t)!
        : Color.lerp(const Color(0xFF2E2E2E), Colors.black, t)!;

    final textTheme = base.textTheme.apply(bodyColor: c, displayColor: c);
    final primaryTextTheme = base.primaryTextTheme.apply(bodyColor: c, displayColor: c);

    final cs = base.colorScheme;
    final newCs = cs.copyWith(
      onSurface: c,
      onBackground: c,
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
    // ✅ "Fondo" debe notarse: controla un *Surface Palette* (fondo + cards + variant)
    // en una escala suave: blanco cálido -> gris -> violeta suave -> petróleo -> negro.
    final idx = level.clamp(1, 10);
    final tRaw = (idx - 1) / 9.0;
    final t = Curves.easeOutCubic.transform(tRaw);

    const warmWhite = Color(0xFFF8F6F2); // no muy blanco
    const softGray = Color(0xFFE9E9EE);
    const softViolet = Color(0xFFEDE6FA); // violeta MUY suave
    const petroleum = Color(0xFF121A1D); // negro medio petróleo
    const deepBlack = Color(0xFF050607); // negro

    Color lerp(Color a, Color b, double tt) => Color.lerp(a, b, tt) ?? a;

    // Interpolación por tramos para que el violeta se note en el medio.
    Color bg;
    if (t < 0.25) {
      bg = lerp(warmWhite, softGray, t / 0.25);
    } else if (t < 0.50) {
      bg = lerp(softGray, softViolet, (t - 0.25) / 0.25);
    } else if (t < 0.78) {
      bg = lerp(softViolet, petroleum, (t - 0.50) / 0.28);
    } else {
      bg = lerp(petroleum, deepBlack, (t - 0.78) / 0.22);
    }

    // Cards: ligeramente diferente al fondo para que se distingan.
    Color shiftLightness(Color c, double delta) {
      final hsl = HSLColor.fromColor(c);
      final l = (hsl.lightness + delta).clamp(0.0, 1.0);
      return hsl.withLightness(l).toColor();
    }

    final isDarkBg = bg.computeLuminance() < 0.42;
    final card = isDarkBg ? shiftLightness(bg, 0.06) : shiftLightness(bg, 0.02);
    final variant = isDarkBg ? shiftLightness(bg, 0.10) : shiftLightness(bg, -0.02);

    final cs = base.colorScheme;
    final newCs = cs.copyWith(
      background: bg,
      surface: card,
      surfaceVariant: variant,
      outline: isDarkBg ? shiftLightness(bg, 0.16) : shiftLightness(bg, -0.18),
    );

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      colorScheme: newCs,
      // ✅ Esto es lo que el usuario quería que se note: el fondo de las cards.
      cardTheme: base.cardTheme.copyWith(color: card),
      // Dialogs / sheets también siguen la paleta.
      dialogTheme: base.dialogTheme.copyWith(backgroundColor: card),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(backgroundColor: card),
      chipTheme: base.chipTheme.copyWith(backgroundColor: variant),
      appBarTheme: base.appBarTheme.copyWith(backgroundColor: bg),
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

                    return MaterialApp(
                      debugShowCheckedModeBanner: false,
                      title: 'Colección vinilos',
                      theme: theme,
                      home: const HomeScreen(),
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

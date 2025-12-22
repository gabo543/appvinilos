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
      // ThemeData.cardTheme espera CardThemeData (no CardTheme).
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 5,
        shadowColor: Color(0x22000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(26)),
          side: BorderSide(color: Color(0xFFF0F0F0)),
        ),
        margin: EdgeInsets.symmetric(vertical: 10),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2),
        titleLarge: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2),
        titleMedium: TextStyle(fontWeight: FontWeight.w800),
        bodyLarge: TextStyle(fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(fontWeight: FontWeight.w500),
        labelLarge: TextStyle(fontWeight: FontWeight.w800),
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

      listTileTheme: const ListTileThemeData(
        iconColor: Colors.white,
        textColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
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
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2, fontSize: 20),
        titleLarge: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2, fontSize: 18),
        titleMedium: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        bodyLarge: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        bodyMedium: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        labelLarge: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0, fontSize: 12),
      ),
      iconTheme: const IconThemeData(color: Colors.white, size: 22),
      dividerColor: const Color(0xFF1A1A1A),
    );
  }


  ThemeData _theme4() {
    // Diseño 4: Pastel Citrus (claro, suave)
    const bg = Color(0xFFF7F7F3);
    const surf = Color(0xFFFFFFFF);
    const accent = Color(0xFF2E7D32); // verde
    const accent2 = Color(0xFFFFA000); // ámbar

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
        surface: surf,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: surf,
        elevation: 1,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      listTileTheme: const ListTileThemeData(iconColor: Colors.black87, textColor: Colors.black87),
      iconTheme: const IconThemeData(color: Colors.black87, size: 22),
      dividerColor: const Color(0xFFE6E6E6),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF0F0F0),
        selectedColor: accent.withOpacity(0.18),
        labelStyle: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(color: Colors.black87),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black87,
          side: const BorderSide(color: Color(0xFFCCCCCC)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent2,
        foregroundColor: Colors.black,
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

  ThemeData _applyTextIntensity(ThemeData base, int level) {
    // level: 0..10 (más niveles = más contraste)
    final isDark = base.brightness == Brightness.dark;
    final t = (level.clamp(0, 10)) / 10.0;

    // Fondo oscuro: desde gris a blanco
    // Fondo claro: desde gris oscuro a negro
    final Color c = isDark
        ? Color.lerp(const Color(0xFFB5B5B5), Colors.white, t)!
        : Color.lerp(const Color(0xFF4A4A4A), Colors.black, t)!
;

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
    // level: 0..4
    final idx = level.clamp(0, 4);
    final isDark = base.brightness == Brightness.dark;

    // 0 = base, 4 = más contraste entre fondo/superficie
    final t = idx / 4.0;
    final bgBase = base.scaffoldBackgroundColor;
    final bgTarget = isDark ? const Color(0xFF060606) : const Color(0xFFF7F7F7);
    final bg = Color.lerp(bgBase, bgTarget, t * 0.55) ?? bgBase;

    return base.copyWith(scaffoldBackgroundColor: bg);
  }

  ThemeData _applyCardLevel(ThemeData base, int level) {
    // level: 0..4
    final idx = level.clamp(0, 4);
    final isDark = base.brightness == Brightness.dark;

    final elev = (idx * 2).toDouble();
    final radius = 12.0 + (idx * 2).toDouble();
    final borderColor = isDark
        ? Color.lerp(const Color(0xFF1A1A1A), const Color(0xFF3A3A3A), idx / 4.0)!
        : Color.lerp(const Color(0xFFE0E0E0), const Color(0xFFBDBDBD), idx / 4.0)!;

    final card = base.cardTheme;
    return base.copyWith(
      cardTheme: card.copyWith(
        elevation: elev,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: borderColor, width: idx == 0 ? 0.5 : 1.0),
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

                    ThemeData theme = _applyTextIntensity(base, intensity);
                    theme = _applyBackgroundLevel(theme, bgLevel);
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

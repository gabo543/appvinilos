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
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 5,
        shadowColor: Color(0x22000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(26)),
          side: BorderSide(color: Color(0xFFF0F0F0)),
        ),
        margin: EdgeInsets.symmetric(vertical: 10),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          side: const BorderSide(color: Color(0xFFE6E6E6)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
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
      cardTheme: const CardThemeData(
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppThemeService.themeNotifier,
      builder: (_, v, __) {
        final ThemeData theme = switch (v) {
          2 => _theme2(),
          3 => _theme3(),
          _ => _theme1(),
        };
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Colección vinilos',
          theme: theme,
          home: const HomeScreen(),
        );
      },
    );
  }
}

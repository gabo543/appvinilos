import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ui/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const GaBoLpApp());
}

class GaBoLpApp extends StatelessWidget {
  const GaBoLpApp({super.key});

  ThemeData _theme() {
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
      cardTheme: CardTheme(
        color: const Color(0xFF161616),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF242424)),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
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
      dividerColor: const Color(0xFF242424),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Colección vinilos',
      theme: _theme(),
      home: const HomeScreen(),
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Colección vinilos',
      theme: ThemeData(useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

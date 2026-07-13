import 'package:flutter/material.dart';
import 'shell/adaptive_shell.dart';
import 'theme/progressor_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProgressorApp());
}

class ProgressorApp extends StatelessWidget {
  const ProgressorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Progressor',
      debugShowCheckedModeBanner: false,
      theme: ProgressorTheme.dark,
      darkTheme: ProgressorTheme.dark,
      themeMode: ThemeMode.dark,
      home: const AdaptiveShell(),
    );
  }
}

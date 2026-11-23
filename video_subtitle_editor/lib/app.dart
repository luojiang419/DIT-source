import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/main_shell.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2D6A4F)),
    );

    return MaterialApp(
      title: '采访视频检索工具',
      theme: baseTheme.copyWith(
        textTheme: GoogleFonts.notoSansScTextTheme(baseTheme.textTheme),
      ),
      home: const MainShell(),
    );
  }
}


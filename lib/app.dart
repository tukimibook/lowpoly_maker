import 'package:flutter/material.dart';

import 'screens/editor_screen.dart';
import 'screens/home_screen.dart';

class PolygonArtApp extends StatelessWidget {
  const PolygonArtApp({super.key});

  static const String homeRoute = '/';
  static const String editorRoute = '/editor';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Polygon Art',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5C6BC0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true),
      ),
      initialRoute: homeRoute,
      routes: {
        homeRoute: (context) => const HomeScreen(),
        editorRoute: (context) => const EditorScreen(),
      },
    );
  }
}

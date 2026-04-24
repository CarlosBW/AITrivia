import 'package:flutter/material.dart';
import '../features/auth/auth_gate.dart';

class TriviaIAApp extends StatelessWidget {
  const TriviaIAApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TriviaIA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const AuthGate(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'login.dart';
import 'register.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final apiBaseUrl = kDebugMode
      ? (const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:5000'))
      : (const String.fromEnvironment('API_BASE_URL', defaultValue: 'https://nexusrdr.com.br'));
  
  print('[MAIN] API_BASE_URL: $apiBaseUrl');
  
  try {
    final healthUri = Uri.parse('$apiBaseUrl/health');
    print('[MAIN] Testando conectividade: $healthUri');
    final resp = await http.get(healthUri).timeout(const Duration(seconds: 5));
    print('[MAIN] /health Status: ${resp.statusCode}, Body: ${resp.body}');
  } catch (e) {
    print('[MAIN] ERRO ao conectar com backend: $e');
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Nexus Financeiro',
      home: LoginPage(),
    );
  }
}

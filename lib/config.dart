import 'package:flutter/foundation.dart';

/// Configuração da URL base da API
/// 
/// Para desenvolvimento mobile (Android/iOS):
/// - Substitua '192.168.1.X' pelo IP local do seu PC na rede
/// - Para descobrir seu IP: ipconfig (Windows) ou ifconfig (Mac/Linux)
/// 
/// Para produção:
/// - Usa https://nexusrdr.com.br
String getApiBaseUrl() {
  if (kDebugMode) {
    // Em debug mode: usa localhost (funciona com ADB reverse para mobile via USB)
    return const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:5000');
  } else {
    // Em produção
    return const String.fromEnvironment('API_BASE_URL', defaultValue: 'https://nexusrdr.com.br');
  }
}

final String apiBaseUrl = getApiBaseUrl();

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
  final override = const String.fromEnvironment('API_BASE_URL');
  if (override.isNotEmpty) return override;
  return 'https://nexusrdr.com.br';
}

final String apiBaseUrl = getApiBaseUrl();

final ValueNotifier<int> financeRefreshTick = ValueNotifier<int>(0);

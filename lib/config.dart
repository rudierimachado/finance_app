import 'dart:io';
import 'package:flutter/foundation.dart';

/// Configuração da URL base da API
/// 
/// Para desenvolvimento local:
/// - Web: http://localhost:5000
/// - Mobile: http://SEU_IP_LOCAL:5000 (ex: http://192.168.1.10:5000)
/// 
/// Para produção:
/// - Usa https://nexusrdr.com.br
String getApiBaseUrl() {
  final override = const String.fromEnvironment('API_BASE_URL');
  if (override.isNotEmpty) return override;
  
  // Desenvolvimento: usar localhost
  if (kDebugMode) {
    // Web usa localhost
    if (kIsWeb) {
      return 'http://localhost:5000';
    }
    // Mobile precisa do IP da máquina na rede
    // Para descobrir seu IP: ipconfig (Windows) ou ifconfig (Mac/Linux)
    // Troque pelo seu IP local:
    return 'http://192.168.1.10:5000'; // ← MUDE AQUI para seu IP
  }
  
  // Produção
  return 'https://nexusrdr.com.br';
}

final String apiBaseUrl = getApiBaseUrl();

final ValueNotifier<int> financeRefreshTick = ValueNotifier<int>(0);

import 'dart:io';
import 'package:flutter/foundation.dart';

/// Configuração da URL base da API
/// 
/// Para desenvolvimento local:
/// - Web: http://localhost:5000
/// - Mobile: http://SEU_IP_LOCAL:5000 (ex: http://192.168.0.104:5000)
/// 
/// Para produção:
/// - Usa https://nexusrdr.com.br
String getApiBaseUrl() {
  final override = const String.fromEnvironment('API_BASE_URL');
  if (override.isNotEmpty) {
    print('[CONFIG] API Base URL override: $override');
    return override;
  }
  
  // Para testar localmente: mude 'false' para 'true'
  // DESENVOLVIMENTO: true = localhost | PRODUÇÃO: false = AWS
  if (kDebugMode) {
    // Web usa localhost
    if (kIsWeb) {
      const url = 'http://localhost:5000';
      print('[CONFIG] API Base URL (Web): $url');
      return url;
    }
    
    // Mobile: detectar se é emulador Android
    if (Platform.isAndroid) {
      // Verificar se é emulador Android (algumas pistas)
      final isEmulator = Platform.environment.containsKey('ANDROID_EMULATOR') || 
                         Platform.environment.containsKey('EMULATOR_HOST_OUT_DIR') ||
                         Platform.environment['ANDROID_SERIAL']?.startsWith('emulator') == true;
      
      if (isEmulator) {
        const url = 'http://10.0.2.2:5000'; // IP especial para emulador Android
        print('[CONFIG] API Base URL (Android Emulator): $url');
        return url;
      } else {
        // Device real Android - usar IP da rede local
        const url = 'http://192.168.0.104:5000'; // IP da máquina host
        print('[CONFIG] API Base URL (Android Device): $url');
        return url;
      }
    } else if (Platform.isIOS) {
      // iOS - usar IP da rede local
      const url = 'http://192.168.0.104:5000'; // IP da máquina host
      print('[CONFIG] API Base URL (iOS): $url');
      return url;
    } else {
      // Outros (fallback para IP local)
      const url = 'http://192.168.0.104:5000';
      print('[CONFIG] API Base URL (Mobile Fallback): $url');
      return url;
    }
  }
  
  // Produção
  const url = 'https://nexusrdr.com.br';
  print('[CONFIG] API Base URL (Production): $url');
  return url;
}

String apiBaseUrl = getApiBaseUrl();

final ValueNotifier<int> financeRefreshTick = ValueNotifier<int>(0);

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:install_plugin/install_plugin.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class AppUpdater {
  static const String _lastCheckKey = 'last_update_check';
  static const Duration _checkInterval = Duration(hours: 6);

  /// Verifica se há atualizações disponíveis automaticamente
  static Future<void> checkForUpdatesAutomatically(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheck = prefs.getInt(_lastCheckKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // Só verificar se passou do intervalo
      if (now - lastCheck < _checkInterval.inMilliseconds) {
        return;
      }
      
      // Salvar timestamp da verificação
      await prefs.setInt(_lastCheckKey, now);
      
      final hasUpdate = await _checkVersionFromServer();
      
      if (hasUpdate && context.mounted) {
        _showUpdateDialog(context, isAutomatic: true);
      }
    } catch (e) {
      // Falha silenciosa para verificação automática
      print('[AUTO_UPDATE] Erro na verificação automática: $e');
    }
  }

  /// Força verificação manual de atualizações
  static Future<void> checkForUpdatesManually(BuildContext context) async {
    _showLoadingDialog(context);
    
    try {
      final hasUpdate = await _checkVersionFromServer();
      
      if (context.mounted) {
        Navigator.of(context).pop(); // Fechar loading
        
        if (hasUpdate) {
          _showUpdateDialog(context, isAutomatic: false);
        } else {
          _showNoUpdateDialog(context);
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Fechar loading
        _showErrorDialog(context, 'Erro ao verificar atualizações: $e');
      }
    }
  }

  /// Verifica se há nova versão disponível no servidor
  static Future<bool> _checkVersionFromServer() async {
    try {
      final dio = Dio();
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      
      // Endpoint para verificar versão (você precisa criar no backend)
      final response = await dio.get(
        '$apiBaseUrl/gerenciamento-financeiro/api/app-version',
        options: Options(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      
      if (response.statusCode == 200) {
        final serverVersion = response.data['version'] as String?;
        
        if (serverVersion != null) {
          return _isNewerVersion(serverVersion, currentVersion);
        }
      }
      
      return false;
    } catch (e) {
      throw Exception('Falha ao verificar versão: $e');
    }
  }

  /// Compara duas versões (formato: "1.0.0")
  static bool _isNewerVersion(String serverVersion, String currentVersion) {
    try {
      final serverParts = serverVersion.split('.').map(int.parse).toList();
      final currentParts = currentVersion.split('.').map(int.parse).toList();
      
      // Garante que ambas tenham 3 partes
      while (serverParts.length < 3) serverParts.add(0);
      while (currentParts.length < 3) currentParts.add(0);
      
      for (int i = 0; i < 3; i++) {
        if (serverParts[i] > currentParts[i]) {
          return true;
        } else if (serverParts[i] < currentParts[i]) {
          return false;
        }
      }
      
      return false; // Versões iguais
    } catch (e) {
      return false;
    }
  }

  /// Inicia o processo de download e instalação
  static Future<void> _startUpdate(BuildContext context) async {
    try {
      // 1. Solicitar permissões
      final hasPermissions = await _requestPermissions();
      if (!hasPermissions) {
        if (context.mounted) {
          _showErrorDialog(context, 'Permissões necessárias não foram concedidas.');
        }
        return;
      }

      // 2. Mostrar progresso
      if (context.mounted) {
        _showDownloadProgressDialog(context);
      }

      // 3. Fazer download
      final apkPath = await _downloadAPK((progress) {
        // Atualizar progresso na UI se possível
        if (context.mounted) {
          // Podemos criar um callback para atualizar o progresso
        }
      });

      // 4. Instalar APK
      if (context.mounted) {
        Navigator.of(context).pop(); // Fechar dialog de progresso
        await _installAPK(apkPath);
      }

    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Fechar qualquer dialog aberto
        _showErrorDialog(context, 'Erro durante atualização: $e');
      }
    }
  }

  /// Solicita permissões necessárias
  static Future<bool> _requestPermissions() async {
    try {
      // Para Android 11+, precisa de permissão para instalar APKs
      if (Platform.isAndroid) {
        final installPermission = await Permission.requestInstallPackages.request();
        
        // Também solicitar permissões de storage se necessário
        final storagePermission = await Permission.storage.request();
        
        return installPermission.isGranted && 
               (storagePermission.isGranted || storagePermission.isPermanentlyDenied);
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Faz download do APK com progresso
  static Future<String> _downloadAPK(Function(double progress)? onProgress) async {
    try {
      final dio = Dio();
      
      // Obter diretório para salvar o APK
      Directory directory;
      if (Platform.isAndroid) {
        directory = await getExternalStorageDirectory() ??
                   await getApplicationDocumentsDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      
      final savePath = '${directory.path}/finance_app_update.apk';
      
      // Deletar arquivo anterior se existir
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }
      
      // Download com progresso
      await dio.download(
        '$apiBaseUrl/gerenciamento-financeiro/download/apk',
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            final progress = received / total;
            onProgress(progress);
          }
        },
        options: Options(
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 5),
        ),
      );
      
      return savePath;
    } catch (e) {
      throw Exception('Falha no download: $e');
    }
  }

  /// Instala o APK baixado
  static Future<void> _installAPK(String apkPath) async {
    try {
      final result = await InstallPlugin.installApk(apkPath, 'com.example.finance_app_new');
      
      if (result['isSuccess'] != true) {
        throw Exception(result['errorMessage'] ?? 'Falha na instalação');
      }
    } catch (e) {
      throw Exception('Erro ao instalar: $e');
    }
  }

  // === DIALOGS DE UI ===

  static void _showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        backgroundColor: Color(0xFF203A43),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF00C9A7)),
            SizedBox(width: 16),
            Text(
              'Verificando atualizações...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  static void _showUpdateDialog(BuildContext context, {required bool isAutomatic}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF203A43),
        title: const Row(
          children: [
            Icon(Icons.system_update, color: Color(0xFF00C9A7)),
            SizedBox(width: 8),
            Text('Atualização Disponível', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          isAutomatic 
              ? 'Uma nova versão está disponível. Deseja baixar e instalar automaticamente?'
              : 'Nova versão encontrada! Instalar agora?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Agora não', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _startUpdate(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C9A7),
              foregroundColor: Colors.white,
            ),
            child: const Text('Atualizar'),
          ),
        ],
      ),
    );
  }

  static void _showNoUpdateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF203A43),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text('App Atualizado', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Você já está usando a versão mais recente!',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C9A7),
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void _showDownloadProgressDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        backgroundColor: Color(0xFF203A43),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF00C9A7)),
            SizedBox(height: 16),
            Text(
              'Baixando atualização...',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'Não feche o app durante o download',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  static void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF203A43),
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text('Erro', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
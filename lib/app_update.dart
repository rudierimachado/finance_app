import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_file_plus/open_file_plus.dart';
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
      
      if (now - lastCheck < _checkInterval.inMilliseconds) return;
      await prefs.setInt(_lastCheckKey, now);
      
      final hasUpdate = await _checkVersionFromServer();
      if (hasUpdate && context.mounted) {
        _showUpdateDialog(context, isAutomatic: true);
      }
    } catch (e) {
      print('[AUTO_UPDATE] Erro na verificação automática: $e');
    }
  }

  /// Força verificação manual de atualizações
  static Future<void> checkForUpdatesManually(BuildContext context) async {
    _showLoadingDialog(context);
    try {
      final hasUpdate = await _checkVersionFromServer();
      if (context.mounted) {
        Navigator.of(context).pop();
        if (hasUpdate) {
          _showUpdateDialog(context, isAutomatic: false);
        } else {
          _showNoUpdateDialog(context);
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        _showErrorDialog(context, 'Erro ao verificar atualizações: $e');
      }
    }
  }

  /// Verifica se há nova versão disponível no servidor
  static Future<bool> _checkVersionFromServer() async {
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = '${packageInfo.version}.${packageInfo.buildNumber}';
      
      final response = await dio.get(
        '$apiBaseUrl/gerenciamento-financeiro/api/app-version',
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

  /// Compara duas versões (formato flexível, ex: "0.0.0.11")
  static bool _isNewerVersion(String serverVersion, String currentVersion) {
    try {
      final serverParts = serverVersion.split('.').map(int.parse).toList();
      final currentParts = currentVersion.split('.').map(int.parse).toList();
      while (serverParts.length < 4) serverParts.add(0);
      while (currentParts.length < 4) currentParts.add(0);
      for (int i = 0; i < serverParts.length; i++) {
        if (serverParts[i] > currentParts[i]) return true;
        if (serverParts[i] < currentParts[i]) return false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  static void _showInstallingDialog(BuildContext context) {
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
            Expanded(
              child: Text(
                'Preparando instalação...\nSe o instalador não abrir, verifique as permissões.',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Inicia o processo de download e instalação
  static Future<void> _startUpdate(BuildContext context) async {
    final progressNotifier = ValueNotifier<double>(0);
    
    try {
      final hasPermissions = await _requestPermissions();
      if (!hasPermissions) {
        if (context.mounted) {
          _showErrorDialog(context, 'Permissão para instalar aplicativos é necessária. Por favor, ative-a nas configurações.');
        }
        return;
      }

      if (context.mounted) _showDownloadProgressDialog(context, progressNotifier);
      
      print('[UPDATE] Iniciando download do APK...');
      final apkPath = await _downloadAPK((progress) {
        progressNotifier.value = progress;
      });
      
      if (context.mounted) {
        print('[UPDATE] Download concluído. Caminho: $apkPath');
        
        // Tenta fechar o diálogo de progresso com segurança
        if (Navigator.canPop(context)) {
          Navigator.of(context).pop(); 
        }
        
        _showInstallingDialog(context);
        
        // Pequeno atraso para garantir que o sistema de arquivos liberou o APK
        await Future.delayed(const Duration(seconds: 1));
        
        print('[UPDATE] Chamando instalação nativa...');
        await _installAPK(apkPath);
        
        // Fecha o diálogo de "Instalando" após um tempo
        await Future.delayed(const Duration(seconds: 3));
        if (context.mounted && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      print('[UPDATE] ERRO: $e');
      if (context.mounted) {
        // Tenta fechar diálogos de carregamento/progresso
        Navigator.of(context).popUntil((route) => route.isFirst);
        _showErrorDialog(context, 'Falha na atualização: $e');
      }
    }
  }

  /// Solicita permissões necessárias
  static Future<bool> _requestPermissions() async {
    try {
      if (Platform.isAndroid) {
        // Permissão para instalar APKs de fontes desconhecidas
        final installStatus = await Permission.requestInstallPackages.request();
        if (installStatus.isGranted) return true;

        if (installStatus.isPermanentlyDenied) {
          await openAppSettings();
        }
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Faz download do APK com progresso
  static Future<String> _downloadAPK(Function(double progress)? onProgress) async {
    try {
      final dio = Dio(
        BaseOptions(
          receiveTimeout: const Duration(minutes: 10),
          sendTimeout: const Duration(minutes: 10),
          followRedirects: true,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      
      // Use sempre external cache directory para APKs
      final directory = await getExternalCacheDirectories();
      final targetDir = directory?.first ?? await getTemporaryDirectory();
      
      final updatesDir = Directory('${targetDir.path}/updates');
      
      if (await updatesDir.exists()) {
        await updatesDir.delete(recursive: true);
      }
      await updatesDir.create(recursive: true);

      final savePath = '${updatesDir.path}/finance_app_update.apk';
      final downloadUrl = '$apiBaseUrl/gerenciamento-financeiro/download/apk';
      
      print('[UPDATE] Baixando de: $downloadUrl');

      final response = await dio.download(
        downloadUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Servidor retornou erro ${response.statusCode}');
      }

      final downloadedFile = File(savePath);
      if (!await downloadedFile.exists()) {
        throw Exception('O arquivo APK não foi salvo.');
      }
      
      final length = await downloadedFile.length();
      print('[UPDATE] Arquivo baixado. Tamanho: ${(length / 1024 / 1024).toStringAsFixed(2)} MB');
      
      if (length < 1000) {
        await downloadedFile.delete();
        throw Exception('Arquivo inválido (muito pequeno).');
      }

      return savePath;
    } catch (e) {
      if (e is DioException) {
        switch (e.type) {
          case DioExceptionType.connectionTimeout:
            throw Exception('Tempo de conexão esgotado');
          case DioExceptionType.receiveTimeout:
            throw Exception('Tempo de download esgotado');
          case DioExceptionType.badResponse:
            throw Exception('Servidor indisponível (${e.response?.statusCode})');
          default:
            throw Exception('Erro de rede: ${e.message}');
        }
      }
      rethrow;
    }
  }

  /// Instala o APK baixado via intent nativa
  static Future<void> _installAPK(String apkPath) async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.requestInstallPackages.status;
        if (!status.isGranted) {
          final result = await Permission.requestInstallPackages.request();
          if (!result.isGranted) {
            throw Exception('Permissão para instalar aplicativos desconhecidos é necessária.');
          }
        }
        await _installAPKAndroid(apkPath);
      } else {
        throw UnsupportedError('Instalação automática só suportada no Android');
      }
    } catch (e) {
      throw Exception('Erro ao instalar: $e');
    }
  }

  /// Instalação no Android via open_file_plus
  static Future<void> _installAPKAndroid(String apkPath) async {
    try {
      final file = File(apkPath);
      if (!await file.exists()) {
        throw Exception('APK não encontrado: $apkPath');
      }

      // Usar open_file_plus que trata FileProvider e Intents automaticamente
      final result = await OpenFile.open(
        apkPath,
        type: "application/vnd.android.package-archive",
      );
      
      if (result.type != ResultType.done) {
        throw Exception('Falha ao abrir instalador: ${result.message}');
      }
    } catch (e) {
      throw Exception('Falha ao invocar instalação: $e');
    }
  }

  // === DIALOGS ===
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
            Text('Verificando atualizações...', style: TextStyle(color: Colors.white)),
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

  static void _showDownloadProgressDialog(BuildContext context, ValueNotifier<double> progressNotifier) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ValueListenableBuilder<double>(
        valueListenable: progressNotifier,
        builder: (context, progress, child) {
          final percent = progress < 0 ? 0 : (progress * 100).toInt();
          return AlertDialog(
            backgroundColor: const Color(0xFF203A43),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_download, color: Color(0xFF00C9A7), size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Baixando atualização...',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                LinearProgressIndicator(
                  value: progress < 0 ? null : progress,
                  backgroundColor: Colors.white10,
                  color: const Color(0xFF00C9A7),
                  minHeight: 8,
                ),
                const SizedBox(height: 12),
                Text(
                  progress < 0 ? 'Calculando tamanho...' : '$percent%',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          );
        },
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
            Icon(Icons.error_outline, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Erro na Atualização', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          message.contains('Exception:') ? message.split('Exception:')[1] : message,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK', style: TextStyle(color: Color(0xFF00C9A7))),
          ),
        ],
      ),
    );
  }
}
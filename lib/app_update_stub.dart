import 'package:flutter/material.dart';

import 'config.dart';

class AppUpdate {
  static Future<void> triggerUpdate(BuildContext context) async {
    final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/download/apk');
    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(
      SnackBar(
        content: Text('Abra este link para baixar a versão mais recente: $uri'),
        duration: const Duration(seconds: 6),
      ),
    );
  }
}

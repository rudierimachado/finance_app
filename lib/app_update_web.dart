import 'dart:html' as html;

import 'package:flutter/material.dart';

class AppUpdate {
  static Future<void> triggerUpdate(BuildContext context) async {
    // Force a reload bypassing cache via a querystring cache-buster.
    final loc = html.window.location;
    final href = loc.href;

    final sep = href.contains('?') ? '&' : '?';
    final next = '$href${sep}reload=${DateTime.now().millisecondsSinceEpoch}';
    html.window.location.replace(next);
  }
}

import 'dart:html' as html;

Future<bool> openExternalUrlImpl(String url) async {
  html.window.open(url, '_blank');
  return true;
}

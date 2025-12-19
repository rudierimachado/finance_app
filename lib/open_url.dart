import 'open_url_stub.dart' if (dart.library.html) 'open_url_web.dart';

/// Abre uma URL externamente.
///
/// - No Web: abre em nova aba/janela.
/// - Em outras plataformas: retorna false.
Future<bool> openExternalUrl(String url) => openExternalUrlImpl(url);

import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'login.dart';
import 'register.dart';
import 'workspace_onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR', null);
  Intl.defaultLocale = 'pt_BR';
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    // Deep link inicial (app frio)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleUri(initialUri);
      }
    } catch (_) {}

    // Deep links em runtime
    _appLinks.uriLinkStream.listen((uri) {
      if (uri != null) _handleUri(uri);
    }, onError: (_) {});
  }

  void _handleUri(Uri uri) {
    // Ex: nexusfinance://workspace/onboarding?workspace_id=123&workspace_name=X&role=viewer&user_id=1
    if (uri.host == 'workspace' && uri.pathSegments.isNotEmpty && uri.pathSegments[0] == 'onboarding') {
      final workspaceId = int.tryParse(uri.queryParameters['workspace_id'] ?? '0') ?? 0;
      final workspaceName = uri.queryParameters['workspace_name'];
      final role = uri.queryParameters['role'];
      final userId = int.tryParse(uri.queryParameters['user_id'] ?? '0') ?? 0;

      if (workspaceId > 0 && navigatorKey.currentState != null) {
        navigatorKey.currentState!.pushNamed(
          '/workspace/onboarding',
          arguments: {
            'workspace_id': workspaceId,
            'workspace_name': workspaceName,
            'role': role,
            'user_id': userId,
          },
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Nexus Finanças',
      routes: {
        '/login': (_) => const LoginPage(),
        '/register': (_) => const RegisterPage(),
        '/workspace/onboarding': (_) => const WorkspaceOnboardingScreen(),
      },
      home: const LoginPage(),
    );
  }
}

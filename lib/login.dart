import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'home_shell.dart';
import 'register.dart';
import 'config.dart';
import 'workspace_selector.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  late AnimationController _mainController;

  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  String? _errorMessage;

  final LocalAuthentication _localAuth = LocalAuthentication();
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    try {
      final enabledRaw = await _secureStorage.read(key: 'biometric_enabled');
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      setState(() {
        _biometricAvailable = canCheck && isDeviceSupported;
        _biometricEnabled = enabledRaw == 'true';
      });

      // Tentar login automático com biometria se credenciais salvas
      if (_biometricAvailable && _biometricEnabled) {
        final savedEmail = await _secureStorage.read(key: 'saved_email');
        if (savedEmail != null) {
          _tryBiometricLogin();
        }
      }
    } catch (e) {
      setState(() {
        _biometricAvailable = false;
        _biometricEnabled = false;
      });
    }
  }

  Future<void> _tryBiometricLogin() async {
    try {
      if (kDebugMode) {
        print('[BIOMETRIC] Iniciando tentativa de login biométrico');
      }
      
      final enabledRaw = await _secureStorage.read(key: 'biometric_enabled');
      if (kDebugMode) {
        print('[BIOMETRIC] biometric_enabled = $enabledRaw');
      }
      if (enabledRaw != 'true') {
        if (kDebugMode) {
          print('[BIOMETRIC] Biometria não habilitada, abortando');
        }
        return;
      }
      
      if (!_biometricAvailable) {
        if (kDebugMode) {
          print('[BIOMETRIC] Biometria não disponível no dispositivo, abortando');
        }
        return;
      }

      if (kDebugMode) {
        print('[BIOMETRIC] Solicitando autenticação biométrica...');
      }
      
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Use sua digital para entrar',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (kDebugMode) {
        print('[BIOMETRIC] Resultado da autenticação: $authenticated');
      }

      if (authenticated) {
        final savedEmail = await _secureStorage.read(key: 'saved_email');
        final savedPassword = await _secureStorage.read(key: 'saved_password');

        if (kDebugMode) {
          print('[BIOMETRIC] Email salvo: ${savedEmail != null ? "SIM" : "NÃO"}');
          print('[BIOMETRIC] Senha salva: ${savedPassword != null ? "SIM" : "NÃO"}');
        }

        if (savedEmail != null && savedPassword != null) {
          if (kDebugMode) {
            print('[BIOMETRIC] Preenchendo credenciais e chamando _submit()');
          }
          _emailController.text = savedEmail;
          _passwordController.text = savedPassword;
          await _submit();
          if (kDebugMode) {
            print('[BIOMETRIC] _submit() concluído');
          }
        } else {
          if (kDebugMode) {
            print('[BIOMETRIC] Credenciais ausentes, mostrando erro');
          }
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Faça login primeiro para usar a biometria.'),
              duration: Duration(seconds: 3),
            ),
          );
          setState(() {
            _errorMessage = 'Faça login para salvar suas credenciais.';
          });
          return;
        }
      } else {
        if (kDebugMode) {
          print('[BIOMETRIC] Autenticação falhou ou foi cancelada');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[BIOMETRIC] Erro durante login biométrico: $e');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro na biometria: $e')),
      );
    }
  }

  void _initAnimations() {
    _mainController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _mainController,
      curve: Curves.easeOutCubic,
    ));

    _mainController.forward();
  }

  @override
  void dispose() {
    _mainController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.lightImpact();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    HapticFeedback.selectionClick();

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    try {
      final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/login');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'email': email,
          'password': password,
        }),
      );

      final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && (data['success'] == true)) {
        if (!mounted) return;

        // Salvar credenciais automaticamente para uso com biometria
        if (kDebugMode) {
          print('[LOGIN] Salvando credenciais: email=$email');
        }
        await _secureStorage.write(key: 'saved_email', value: email);
        await _secureStorage.write(key: 'saved_password', value: password);
        final verifyEmail = await _secureStorage.read(key: 'saved_email');
        final verifyPassword = await _secureStorage.read(key: 'saved_password');
        if (kDebugMode) {
          print('[LOGIN] Verificação storage: email=${verifyEmail != null ? "SIM" : "NÃO"}, senha=${verifyPassword != null ? "SIM" : "NÃO"}');
        }

        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 800));

        if (mounted) {
          final user = data['user'] as Map<String, dynamic>?;
          final userId = (user?['id'] as num?)?.toInt() ?? 0;

          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (context, animation, _) => WorkspaceSelectorPage(userId: userId),
              transitionDuration: const Duration(milliseconds: 600),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1.0, 0.0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                  child: FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                );
              },
            ),
          );
        }
      } else {
        HapticFeedback.vibrate();
        setState(() {
          _errorMessage = data['message']?.toString() ?? 'Falha ao entrar. Tente novamente.';
        });
      }
    } catch (e) {
      HapticFeedback.vibrate();
      setState(() {
        _errorMessage = 'Não foi possível conectar ao servidor: ${e.runtimeType}: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0F2027),
                Color(0xFF203A43),
                Color(0xFF2C5364),
              ],
            ),
          ),
          child: Stack(
            children: [
              _buildMainContent(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final keyboardBottom = MediaQuery.of(context).viewInsets.bottom;
          final keyboardOpen = keyboardBottom > 0;
          final verticalPadding = keyboardOpen ? 16.0 : 40.0;

          return AnimatedPadding(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: keyboardBottom),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: verticalPadding),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Align(
                  alignment: keyboardOpen ? Alignment.topCenter : Alignment.center,
                  child: AnimatedBuilder(
                    animation: _mainController,
                    builder: (context, child) {
                      return FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: _buildLoginForm(),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoginForm() {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        children: [
          if (keyboardOpen) _buildCompactHeader(),
          if (!keyboardOpen) _buildHeader(),
          SizedBox(height: keyboardOpen ? 12 : 40),
          _buildCard(),
        ],
      ),
    );
  }

  Widget _buildCompactHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF00C9A7).withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF00C9A7).withOpacity(0.35)),
            ),
            child: const Icon(Icons.savings_outlined, color: Color(0xFF00C9A7), size: 16),
          ),
          const SizedBox(width: 10),
          const Text(
            'Nexus Finanças',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00C9A7), Color(0xFF00B4D8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00C9A7).withOpacity(0.28),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: const Icon(
            Icons.savings_outlined,
            color: Colors.white,
            size: 44,
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Nexus Finanças',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }

  Widget _buildCard() {
    final narrow = MediaQuery.of(context).size.width < 380;
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Container(
      padding: EdgeInsets.all(narrow || keyboardOpen ? 20 : 32),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 30,
            offset: const Offset(0, 15),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildWelcomeText(),
            const SizedBox(height: 32),
            _buildEmailField(),
            const SizedBox(height: 20),
            _buildPasswordField(),
            const SizedBox(height: 12),
            _buildRememberAndForgot(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 20),
              _buildErrorMessage(),
            ],
            const SizedBox(height: 32),
            _buildLoginButton(),
            if (_biometricAvailable && _biometricEnabled) ...[
              const SizedBox(height: 16),
              _buildBiometricButton(),
            ],
            const SizedBox(height: 24),
            _buildDivider(),
            const SizedBox(height: 24),
            _buildRegisterButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeText() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bem-vindo de volta!',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2C5364),
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Faça login para continuar',
          style: TextStyle(
            fontSize: 16,
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return _ModernTextField(
      controller: _emailController,
      label: 'E-mail',
      icon: Icons.alternate_email,
      keyboardType: TextInputType.emailAddress,
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) {
          return 'Digite seu e-mail';
        }
        final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
        if (!emailRegex.hasMatch(text)) {
          return 'E-mail inválido';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return _ModernTextField(
      controller: _passwordController,
      label: 'Senha',
      icon: Icons.lock_outline,
      obscureText: _obscurePassword,
      suffixIcon: IconButton(
        icon: Icon(
          _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          color: const Color(0xFF00C9A7),
        ),
        onPressed: () {
          setState(() {
            _obscurePassword = !_obscurePassword;
          });
        },
      ),
      validator: (value) {
        final text = value ?? '';
        if (text.isEmpty) {
          return 'Digite sua senha';
        }
        if (text.length < 6) {
          return 'Mínimo 6 caracteres';
        }
        return null;
      },
    );
  }

  Widget _buildRememberAndForgot() {
    return Row(
      children: [
        Transform.scale(
          scale: 0.9,
          child: Checkbox(
            value: _rememberMe,
            onChanged: (value) {
              setState(() {
                _rememberMe = value ?? false;
              });
            },
            activeColor: const Color(0xFF00C9A7),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const Text(
          'Lembrar de mim',
          style: TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 14,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const RegisterPage(),
              ),
            );
          },
          child: const Text(
            'Esqueceu a senha?',
            style: TextStyle(
              color: Color(0xFF00C9A7),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF5722).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: Color(0xFFFF5722),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                color: Color(0xFFFF5722),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00C9A7), Color(0xFF00B4D8)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00C9A7).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isLoading ? null : _submit,
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Entrar',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildBiometricButton() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF00C9A7), width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isLoading ? null : _tryBiometricLogin,
          child: const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.fingerprint,
                  color: Color(0xFF00C9A7),
                  size: 28,
                ),
                SizedBox(width: 12),
                Text(
                  'Entrar com digital',
                  style: TextStyle(
                    color: Color(0xFF00C9A7),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: const Color(0xFFE5E7EB),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'ou',
            style: TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: const Color(0xFFE5E7EB),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterButton() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF00C9A7), width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const RegisterPage(),
              ),
            );
          },
          child: const Center(
            child: Text(
              'Criar conta',
              style: TextStyle(
                color: Color(0xFF00C9A7),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModernTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;

  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const _ModernTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: Color(0xFF1F2937),
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF00C9A7), size: 22),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF00C9A7), width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFF5722)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFF5722), width: 2),
        ),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        contentPadding: const EdgeInsets.all(16),
        labelStyle: const TextStyle(
          color: Color(0xFF6B7280),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
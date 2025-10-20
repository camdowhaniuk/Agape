import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../utils/form_validators.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  int _passwordStrength = 0;

  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _confirmFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();

    // Listen to password changes for strength indicator
    _passwordController.addListener(() {
      setState(() {
        _passwordStrength = FormValidators.calculatePasswordStrength(
          _passwordController.text,
        );
      });
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmFocusNode.dispose();
    super.dispose();
  }

  void _validateEmail() {
    setState(() {
      _emailError = FormValidators.validateEmail(_emailController.text);
    });
  }

  void _validatePassword() {
    setState(() {
      _passwordError = FormValidators.validatePassword(
        _passwordController.text,
        checkStrength: true,
      );
    });
  }

  void _validateConfirm() {
    setState(() {
      _confirmError = FormValidators.validatePasswordConfirmation(
        _confirmController.text,
        _passwordController.text,
      );
    });
  }

  bool get _isFormValid {
    return _emailController.text.trim().isNotEmpty &&
        _passwordController.text.isNotEmpty &&
        _confirmController.text.isNotEmpty &&
        _emailError == null &&
        _passwordError == null &&
        _confirmError == null;
  }

  Future<void> _register() async {
    // Validate all fields
    _validateEmail();
    _validatePassword();
    _validateConfirm();

    if (!_isFormValid) return;

    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      await _authService.signUpWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );
      // AuthGate will handle navigation on auth state change
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (e) {
      if (mounted) {
        // Print full error details for debugging
        print('Registration error: $e');
        setState(() => _error = 'Error: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // --- Logo ---
                    Image.asset(
                      'assets/agape_logo.png',
                      width: 100,
                      height: 100,
                    ),
                    const SizedBox(height: 20),

                    // --- Title ---
                    Text(
                      'Create Account',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Join the community',
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 36),

                    // --- Global Error Message ---
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(color: Colors.red, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // --- Email ---
                    TextField(
                      controller: _emailController,
                      focusNode: _emailFocusNode,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) {
                        if (_emailError != null) _validateEmail();
                      },
                      onSubmitted: (_) {
                        _passwordFocusNode.requestFocus();
                      },
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email_rounded),
                        errorText: _emailError,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // --- Password ---
                    TextField(
                      controller: _passwordController,
                      focusNode: _passwordFocusNode,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) {
                        if (_passwordError != null) _validatePassword();
                        if (_confirmError != null && _confirmController.text.isNotEmpty) {
                          _validateConfirm();
                        }
                      },
                      onSubmitted: (_) {
                        _confirmFocusNode.requestFocus();
                      },
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() => _obscurePassword = !_obscurePassword);
                          },
                        ),
                        errorText: _passwordError,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                          ),
                        ),
                      ),
                    ),

                    // --- Password Strength Indicator ---
                    if (_passwordController.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: (_passwordStrength + 1) / 4,
                                      minHeight: 6,
                                      backgroundColor: isDark ? Colors.grey[800] : Colors.grey[300],
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(FormValidators.getPasswordStrengthColor(_passwordStrength)),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  FormValidators.getPasswordStrengthLabel(_passwordStrength),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(FormValidators.getPasswordStrengthColor(_passwordStrength)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),

                    // --- Confirm Password ---
                    TextField(
                      controller: _confirmController,
                      focusNode: _confirmFocusNode,
                      obscureText: _obscureConfirm,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) {
                        if (_confirmError != null) _validateConfirm();
                      },
                      onSubmitted: (_) {
                        if (_isFormValid) _register();
                      },
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() => _obscureConfirm = !_obscureConfirm);
                          },
                        ),
                        errorText: _confirmError,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- Register Button ---
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isFormValid && !_loading
                              ? colorScheme.primary
                              : (isDark ? Colors.grey[800] : Colors.grey[300]),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: _isFormValid && !_loading ? 2 : 0,
                        ),
                        onPressed: _isFormValid && !_loading ? _register : null,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Sign Up',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // --- Back to Login ---
                    GestureDetector(
                      onTap: _loading
                          ? null
                          : () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(builder: (_) => const LoginScreen()),
                              );
                            },
                      child: Text(
                        "Already have an account? Log in",
                        style: TextStyle(
                          color: _loading
                              ? (isDark ? Colors.grey[600] : Colors.grey[400])
                              : colorScheme.primary,
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

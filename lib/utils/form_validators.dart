// lib/utils/form_validators.dart

class FormValidators {
  /// Validates email format
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email address';
    }

    return null;
  }

  /// Validates password length and strength
  static String? validatePassword(String? value, {bool checkStrength = false}) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }

    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }

    if (checkStrength && value.length < 8) {
      return 'For better security, use 8+ characters';
    }

    return null;
  }

  /// Validates password confirmation match
  static String? validatePasswordConfirmation(String? value, String? password) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }

    if (value != password) {
      return 'Passwords do not match';
    }

    return null;
  }

  /// Calculates password strength (0-3: weak, medium, strong, very strong)
  static int calculatePasswordStrength(String password) {
    if (password.isEmpty) return 0;

    int strength = 0;

    // Length check
    if (password.length >= 8) strength++;
    if (password.length >= 12) strength++;

    // Character variety
    if (RegExp(r'[A-Z]').hasMatch(password)) strength++;
    if (RegExp(r'[a-z]').hasMatch(password)) strength++;
    if (RegExp(r'[0-9]').hasMatch(password)) strength++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) strength++;

    // Return normalized strength (0-3)
    if (strength <= 2) return 0; // weak
    if (strength <= 3) return 1; // medium
    if (strength <= 4) return 2; // strong
    return 3; // very strong
  }

  /// Get password strength label
  static String getPasswordStrengthLabel(int strength) {
    switch (strength) {
      case 0:
        return 'Weak';
      case 1:
        return 'Medium';
      case 2:
        return 'Strong';
      case 3:
        return 'Very Strong';
      default:
        return '';
    }
  }

  /// Get password strength color
  static int getPasswordStrengthColor(int strength) {
    switch (strength) {
      case 0:
        return 0xFFEF5350; // red
      case 1:
        return 0xFFFF9800; // orange
      case 2:
        return 0xFF66BB6A; // green
      case 3:
        return 0xFF4CAF50; // dark green
      default:
        return 0xFF9E9E9E; // grey
    }
  }
}

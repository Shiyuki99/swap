import 'package:flutter/material.dart';

class AppColors {
  /// Set by ThemeProvider — drives all dynamic getters below.
  static bool _isDark = false;

  // Backgrounds
  static Color get mainBg =>
      _isDark ? const Color(0xFF121212) : const Color(0xFFFFFFFF);
  static Color get buttonBg =>
      _isDark ? const Color(0xFF2C2C2C) : const Color(0xFF1E1E1E);
  static const deleteBg = Color(0xFFEC221F);
  static const openBg = Color(0xFF806CF1);
  static Color get inputBg =>
      _isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3);
  static Color get cardBg =>
      _isDark ? const Color(0xFF2A2A2A) : const Color(0xFFD9D9D9);

  // Text
  static Color get mainText =>
      _isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
  static Color get secondaryText =>
      _isDark ? const Color(0xFFA0A0A0) : const Color(0xFF666666);
  static const lightText = Color(0xFFFFFFFF);

  // States
  static const successGreen = Color(0xFF1EF799);
  static const checkmarkGreen = Color(0xFF00C853);
  static const disabled = Color(0xFFBDBDBD);
  static const attentionAmber = Color(0xFFFFA726);

  // Socials
  static const instagram = Color(0xFFE1306C);
  static const discord = Color(0xFF5865F2);
  static Color get github =>
      _isDark ? const Color(0xFFE0E0E0) : const Color(0xFF181717);
  static Color get twitter =>
      _isDark ? const Color(0xFFE0E0E0) : const Color(0xFF000000);
  static Color get tiktok =>
      _isDark ? const Color(0xFFE0E0E0) : const Color(0xFF000000);
  static const phone = Color(0xFF4DB6AC);
  static const email = Color(0xFF4FC3F7);

  static bool get isDark => _isDark;
  static void setTheme(bool isDark) => _isDark = isDark;
}

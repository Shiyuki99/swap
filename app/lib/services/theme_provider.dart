import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/colors.dart';

const _kDarkModeKey = 'dark_mode';

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  ThemeProvider() {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool(_kDarkModeKey) ?? false;
    AppColors.setTheme(_isDarkMode);
    notifyListeners();
  }

  Future<void> toggleDarkMode() async {
    _isDarkMode = !_isDarkMode;
    AppColors.setTheme(_isDarkMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDarkModeKey, _isDarkMode);
    notifyListeners();
  }
}

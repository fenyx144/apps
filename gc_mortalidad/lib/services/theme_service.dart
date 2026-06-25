import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

class ThemeService extends ChangeNotifier {
  ThemeService(this._prefs) {
    _mode = _loadSavedMode();
  }

  final SharedPreferences _prefs;
  late ThemeMode _mode;

  ThemeMode get mode => _mode;

  String get modeLabel {
    switch (_mode) {
      case ThemeMode.light:
        return AppStrings.menuModoClaro;
      case ThemeMode.dark:
        return AppStrings.menuModoOscuro;
      default:
        return AppStrings.menuModoClaro;
    }
  }

  IconData get modeIcon {
    switch (_mode) {
      case ThemeMode.light:
        return Icons.light_mode_rounded;
      case ThemeMode.dark:
        return Icons.dark_mode_rounded;
      default:
        return Icons.light_mode_rounded;
    }
  }

  ThemeMode _loadSavedMode() {
    final saved = _prefs.getString(AppConstants.keyThemeMode);
    switch (saved) {
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.light;
    }
  }

  String _modeToStorage(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      default:
        return 'light';
    }
  }

  Future<void> toggleTheme() async {
    switch (_mode) {
      case ThemeMode.light:
        _mode = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        _mode = ThemeMode.light;
        break;
      default:
        _mode = ThemeMode.light;
    }
    await _persistMode();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _mode = mode;
    await _persistMode();
  }

  Future<void> _persistMode() async {
    await _prefs.setString(AppConstants.keyThemeMode, _modeToStorage(_mode));
    notifyListeners();
  }
}

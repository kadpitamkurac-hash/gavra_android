/// 🔐 CONFIG SERVICE
/// Upravlja kredencijalima aplikacije (Supabase URL, keys, etc.)
/// Učitava iz .env fajla ili environment varijabli
library;

import 'package:flutter_dotenv/flutter_dotenv.dart';

class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  String _supabaseUrl = '';
  String _supabaseAnonKey = '';
  String _supabaseServiceRoleKey = '';
  String _storePassword = '';
  String _keyPassword = '';
  String _keyAlias = '';

  /// Inicijalizuj osnovne kredencijale (iz environment varijabli --dart-define ili .env fajla)
  Future<void> initializeBasic() async {
    // Učitaj .env fajl ako postoji
    await dotenv.load(fileName: '.env');

    // Učitaj iz environment varijabli (--dart-define), ili iz .env fajla
    _supabaseUrl = const String.fromEnvironment('SUPABASE_URL', defaultValue: '');
    if (_supabaseUrl.isEmpty) {
      _supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    }

    _supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
    if (_supabaseAnonKey.isEmpty) {
      _supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
    }

    _supabaseServiceRoleKey = const String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY', defaultValue: '');
    if (_supabaseServiceRoleKey.isEmpty) {
      _supabaseServiceRoleKey = dotenv.env['SUPABASE_SERVICE_ROLE_KEY'] ?? '';
    }

    if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
      throw Exception(
          'Osnovni kredencijali nisu postavljeni. Postavite SUPABASE_URL i SUPABASE_ANON_KEY kao --dart-define varijable pri pokretanju aplikacije ili dodajte ih u .env fajl.');
    }

    // Učitaj keystore podatke
    _loadKeystoreFromEnv();
  }

  /// Inicijalizuj kredencijale (stari metod - zadržan za kompatibilnost)
  Future<void> initialize() async {
    await initializeBasic();
    // Vault credentials više nisu potrebni
  }

  /// Učitaj keystore podatke iz environment varijabli
  void _loadKeystoreFromEnv() {
    // Učitaj iz environment varijabli (--dart-define)
    _storePassword = const String.fromEnvironment('KEYSTORE_PASSWORD', defaultValue: '');
    _keyPassword = const String.fromEnvironment('KEY_PASSWORD', defaultValue: '');
    _keyAlias = const String.fromEnvironment('KEY_ALIAS', defaultValue: '');

    // 🔐 VAŽNO: Keystore kredencijali MORAJU biti postavljeni!
    // Nikada se ne postavljaju default vrednosti jer su to tajne!
    if (_storePassword.isEmpty || _keyPassword.isEmpty || _keyAlias.isEmpty) {
      throw Exception(
          '❌ Keystore kredencijali nisu postavljeni! Postavite KEYSTORE_PASSWORD, KEY_PASSWORD i KEY_ALIAS kao --dart-define varijable pri pokretanju aplikacije.');
    }
  }

  String getSupabaseUrl() => _supabaseUrl;
  String getSupabaseAnonKey() => _supabaseAnonKey;
  String getSupabaseServiceRoleKey() => _supabaseServiceRoleKey;
  String getStorePassword() => _storePassword;
  String getKeyPassword() => _keyPassword;
  String getKeyAlias() => _keyAlias;

  String getDebugInfo() {
    final anonKeyPreview = _supabaseAnonKey.length > 10 ? '${_supabaseAnonKey.substring(0, 10)}...' : '***';
    return 'URL: $_supabaseUrl, AnonKey: $anonKeyPreview, ServiceKey: ${_supabaseServiceRoleKey.isNotEmpty ? "Postavljen ✓" : "Nije postavljen ✗"}';
  }
}

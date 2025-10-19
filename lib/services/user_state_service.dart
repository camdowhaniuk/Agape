import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class UserStateService {
  UserStateService._();

  static final UserStateService instance = UserStateService._();

  static const _fileName = 'user_state.json';
  Map<String, dynamic> _cache = const {};
  bool _loaded = false;
  File? _file;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_fileName');
    _file = file;
    if (await file.exists()) {
      try {
        final raw = await file.readAsString();
        if (raw.isNotEmpty) {
          _cache = json.decode(raw) as Map<String, dynamic>;
        }
      } catch (_) {
        _cache = const {};
      }
    } else {
      await file.create(recursive: true);
      _cache = const {};
    }
    _loaded = true;
  }

  Future<String?> readString(String key) async {
    await _ensureLoaded();
    final value = _cache[key];
    if (value is String) return value;
    return null;
  }

  Future<void> writeString(String key, String value) async {
    await _ensureLoaded();
    _cache = Map<String, dynamic>.from(_cache)..[key] = value;
    final file = _file;
    if (file == null) return;
    await file.writeAsString(json.encode(_cache));
  }
}

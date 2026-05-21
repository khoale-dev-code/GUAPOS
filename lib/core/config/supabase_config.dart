import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart'; // Để dùng kDebugMode

class SupabaseConfig {
  static const String url =
      'https://nlwxhwourmvcuvnchwtw.supabase.co'; // Thay bằng URL thật của bạn
  static const String anonKey =
      'sb_publishable_DKYQUB-hq23QioPwINNm9w_B8e6MNH-'; // Thay bằng Anon Key thật

  static Future<void> init() async {
    try {
      await Supabase.initialize(url: url, anonKey: anonKey);
      if (kDebugMode) {
        print("✅ Supabase đã khởi tạo thành công!");
      }
    } catch (e) {
      if (kDebugMode) {
        print("❌ Lỗi khởi tạo Supabase: $e");
      }
      rethrow;
    }
  }
}

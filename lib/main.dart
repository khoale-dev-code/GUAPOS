import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/config/supabase_config.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  try {
    await SupabaseConfig.init();
    debugPrint('🚀 Supabase đã khởi tạo thành công!');
  } catch (e) {
    debugPrint('❌ Thất bại khi kết nối Supabase: $e');
  }

  runApp(const App());
}

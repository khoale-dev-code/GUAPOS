import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/shell/main_shell.dart';
import 'features/auth/presentation/pin_screen.dart';

// Bỏ GoRouter — app nội bộ nhỏ dùng IndexedStack là đủ
// app_router.dart giữ lại nhưng không dùng nữa

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nhà Vườn',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      // AuthGate kiểm tra PIN → nếu pass thì vào MainShell
      home: AuthGate(
        child: const MainShell(),
      ),
    );
  }
}

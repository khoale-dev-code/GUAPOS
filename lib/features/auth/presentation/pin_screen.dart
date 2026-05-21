import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// PIN SCREEN
// Màn hình khoá app bằng mã PIN 4 số
//
// Flow:
//   Lần đầu mở app  → Đăng nhập Supabase (email/pass ẩn) → Tạo PIN
//   Những lần sau   → Nhập PIN → Vào app
//   Quên PIN        → Nhập email + password để reset
// ============================================================

const _kPinKey = 'app_pin';
const _kLoggedKey = 'is_logged_in';

class PinScreen extends StatefulWidget {
  /// true = đang tạo PIN lần đầu, false = xác nhận PIN
  final bool isSetup;
  final VoidCallback onSuccess;

  const PinScreen({
    super.key,
    required this.isSetup,
    required this.onSuccess,
  });

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  String? _firstPin; // dùng khi setup để xác nhận lần 2
  bool _isConfirming = false; // bước xác nhận PIN lần 2
  bool _showForgot = false;
  int _failCount = 0;

  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  // ── Nhập số ─────────────────────────────────────────────
  void _onDigit(String d) {
    if (_pin.length >= 4) return;
    HapticFeedback.lightImpact();
    setState(() => _pin += d);
    if (_pin.length == 4) {
      Future.delayed(const Duration(milliseconds: 120), _onComplete);
    }
  }

  void _onDelete() {
    if (_pin.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  // ── Hoàn thành nhập PIN ──────────────────────────────────
  Future<void> _onComplete() async {
    if (widget.isSetup) {
      if (!_isConfirming) {
        // Bước 1: lưu PIN tạm, chuyển sang xác nhận
        setState(() {
          _firstPin = _pin;
          _pin = '';
          _isConfirming = true;
        });
      } else {
        // Bước 2: kiểm tra khớp
        if (_pin == _firstPin) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kPinKey, _pin);
          await prefs.setBool(_kLoggedKey, true);
          widget.onSuccess();
        } else {
          _shake();
          setState(() {
            _pin = '';
            _isConfirming = false;
            _firstPin = null;
          });
          _showSnack('PIN không khớp, nhập lại từ đầu');
        }
      }
    } else {
      // Xác nhận PIN
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kPinKey);
      if (_pin == saved) {
        widget.onSuccess();
      } else {
        _shake();
        setState(() {
          _pin = '';
          _failCount++;
        });
        if (_failCount >= 5) {
          setState(() => _showForgot = true);
        }
        _showSnack('Mã PIN không đúng');
      }
    }
  }

  void _shake() {
    HapticFeedback.mediumImpact();
    _shakeCtrl.forward(from: 0);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFFF3B30),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Quên PIN → reset bằng email/pass ────────────────────
  void _showResetDialog() {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool loading = false;

    showCupertinoDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => CupertinoAlertDialog(
          title: const Text('Đặt lại PIN'),
          content: Column(
            children: [
              const SizedBox(height: 8),
              const Text(
                'Nhập email và mật khẩu tài khoản để đặt lại PIN',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: emailCtrl,
                placeholder: 'Email',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: passCtrl,
                placeholder: 'Mật khẩu',
                obscureText: true,
              ),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Huỷ'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: loading
                  ? null
                  : () async {
                      setS(() => loading = true);
                      try {
                        await Supabase.instance.client.auth.signInWithPassword(
                          email: emailCtrl.text.trim(),
                          password: passCtrl.text,
                        );
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove(_kPinKey);
                        if (ctx.mounted) Navigator.pop(ctx);
                        // Reload → sẽ vào flow setup PIN
                        if (mounted) {
                          setState(() {
                            _pin = '';
                            _failCount = 0;
                            _showForgot = false;
                          });
                        }
                      } catch (_) {
                        setS(() => loading = false);
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          _showSnack('Email hoặc mật khẩu không đúng');
                        }
                      }
                    },
              child: Text(loading ? 'Đang xác thực...' : 'Xác nhận'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.isSetup
        ? (_isConfirming
            ? 'Nhập lại PIN để xác nhận'
            : 'Tạo mã PIN 4 số cho app')
        : 'Nhập mã PIN để mở app';

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),

            // Logo / Icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF34C759), Color(0xFF007AFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF34C759).withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Center(
                child: Text('🌿', style: TextStyle(fontSize: 40)),
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              'Nhà Vườn',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade500,
              ),
            ),

            const SizedBox(height: 48),

            // PIN dots với shake animation
            AnimatedBuilder(
              animation: _shakeAnim,
              builder: (_, child) {
                final offset =
                    8 * _shakeAnim.value * (1 - _shakeAnim.value) * 4;
                return Transform.translate(
                  offset: Offset(
                      offset *
                          ((_shakeCtrl.value * 10).round().isEven ? 1 : -1),
                      0),
                  child: child,
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children:
                    List.generate(4, (i) => _PinDot(filled: i < _pin.length)),
              ),
            ),

            const Spacer(),

            // Numpad
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  for (var row in [
                    ['1', '2', '3'],
                    ['4', '5', '6'],
                    ['7', '8', '9'],
                    ['', '0', '⌫'],
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: row.map((d) {
                          if (d.isEmpty) return const SizedBox(width: 76);
                          if (d == '⌫') {
                            return _NumKey(
                              label: d,
                              isDelete: true,
                              onTap: _onDelete,
                            );
                          }
                          return _NumKey(
                            label: d,
                            onTap: () => _onDigit(d),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),

            // Quên PIN
            if (_showForgot || widget.isSetup == false)
              TextButton(
                onPressed: _showResetDialog,
                child: Text(
                  'Quên mã PIN?',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                  ),
                ),
              ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ── PIN Dot ──────────────────────────────────────────────────
class _PinDot extends StatelessWidget {
  final bool filled;
  const _PinDot({required this.filled});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(horizontal: 10),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? const Color(0xFF007AFF) : Colors.transparent,
        border: Border.all(
          color: filled ? const Color(0xFF007AFF) : Colors.grey.shade300,
          width: 2,
        ),
      ),
    );
  }
}

// ── Number Key ───────────────────────────────────────────────
class _NumKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isDelete;

  const _NumKey({
    required this.label,
    required this.onTap,
    this.isDelete = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDelete ? Colors.transparent : Colors.white,
      borderRadius: BorderRadius.circular(38),
      clipBehavior: Clip.antiAlias,
      elevation: isDelete ? 0 : 0,
      shadowColor: Colors.black12,
      child: InkWell(
        onTap: onTap,
        splashColor: const Color(0xFF007AFF).withOpacity(0.1),
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDelete ? Colors.transparent : Colors.white,
            boxShadow: isDelete
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Center(
            child: isDelete
                ? Icon(
                    CupertinoIcons.delete_left_fill,
                    size: 22,
                    color: Colors.grey.shade500,
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w300,
                      letterSpacing: -0.5,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// AUTH GATE – Widget bọc ngoài app để kiểm tra PIN
// Dùng trong main.dart thay vì MaterialApp.router trực tiếp
// ============================================================

class AuthGate extends StatefulWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _hasPin = false;
  bool _checking = true;
  DateTime? _backgroundTime;

  // Khoá lại sau 5 phút background
  static const _lockAfter = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPin();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Tự động khoá khi vào background lâu
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_backgroundTime != null &&
          DateTime.now().difference(_backgroundTime!) > _lockAfter) {
        setState(() => _unlocked = false);
      }
    }
  }

  Future<void> _checkPin() async {
    // Kiểm tra Supabase session
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      // Chưa đăng nhập → cần setup (cho đơn giản, dùng 1 account hardcode
      // hoặc Khoa có thể tạo account trong Supabase dashboard rồi điền vào đây)
      await _autoLogin();
    }

    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString(_kPinKey);
    setState(() {
      _hasPin = savedPin != null && savedPin.isNotEmpty;
      _checking = false;
    });
  }

  // Auto-login với account cố định (nội bộ 1 doanh nghiệp)
  // Khoa tạo account trong Supabase dashboard rồi điền vào đây
  Future<void> _autoLogin() async {
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: 'owner@nha-vuon.com', // ← THAY bằng email thật
        password: 'your_password_here', // ← THAY bằng password thật
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFFF2F2F7),
        body: Center(child: CupertinoActivityIndicator()),
      );
    }

    if (_unlocked) return widget.child;

    return PinScreen(
      isSetup: !_hasPin,
      onSuccess: () => setState(() => _unlocked = true),
    );
  }
}

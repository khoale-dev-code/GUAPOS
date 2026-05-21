import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/models/livestream_models.dart';

class LuckyWheelScreen extends StatefulWidget {
  final LiveSession session; // Nhận cấu hình phiên live độc lập từ màn hình Hub

  const LuckyWheelScreen({super.key, required this.session});

  @override
  State<LuckyWheelScreen> createState() => _LuckyWheelScreenState();
}

class _LuckyWheelScreenState extends State<LuckyWheelScreen>
    with SingleTickerProviderStateMixin {
  final _db = Supabase.instance.client;
  RealtimeChannel? _realtimeChannel;

  List<String> _participants = [];
  bool _loading = true;
  bool _spinning = false;
  String _giftName = 'Cây Lan Quà Tặng';

  late AnimationController _spinCtrl;
  late Animation<double> _spinAnim;
  double _currentAngle = 0;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(vsync: this);
    _loadInitialParticipants();
    _subscribeToLiveComments(); // Lắng nghe luồng comment thời gian thực
  }

  @override
  void dispose() {
    if (_realtimeChannel != null) {
      _db.removeChannel(_realtimeChannel!);
    }
    _spinCtrl.dispose();
    super.dispose();
  }

  // 1. Tải danh sách người dùng đã bình luận từ đầu phiên Live
  Future<void> _loadInitialParticipants() async {
    setState(() => _loading = true);
    try {
      final res = await _db
          .from('livestream_comments')
          .select('commenter_name')
          .eq('session_id', widget.session.id);

      final names = (res as List)
          .map((e) => e['commenter_name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toSet() // Sử dụng Set loại bỏ hiện tượng trùng lặp khi 1 người bình luận nhiều lần
          .toList();

      setState(() => _participants = names);
    } catch (e) {
      debugPrint('Lỗi nạp danh sách ban đầu: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // 2. Đồng bộ Realtime: Sửa lỗi PostgresFilterType cũ của Supabase
  void _subscribeToLiveComments() {
    _realtimeChannel =
        _db.channel('public:livestream_comments').onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'livestream_comments',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'session_id',
                value: widget.session.id,
              ),
              callback: (payload) {
                final newName =
                    payload.newRecord['commenter_name'] as String? ?? '';
                if (newName.isNotEmpty && !_participants.contains(newName)) {
                  setState(() {
                    _participants.add(newName);
                  });
                }
              },
            )..subscribe();
  }

  // 3. Xử lý kích hoạt động cơ vòng xoay
  void _spin() {
    if (_spinning || _participants.length < 2) {
      _showError('Cần tối thiểu 2 thành viên tương tác để quay thưởng');
      return;
    }

    HapticFeedback.heavyImpact();
    setState(() {
      _spinning = true;
    });

    final rng = Random();
    final winnerIndex = rng.nextInt(_participants.length);
    final winner = _participants[winnerIndex];

    // Tính toán góc quay toán học chính xác
    final anglePerSlice = 2 * pi / _participants.length;
    final winnerAngle = (winnerIndex * anglePerSlice) + (anglePerSlice / 2);

    // Tối ưu hóa biến hằng số từ final sang const theo khuyến nghị của Dart compiler
    const extraSpins = 8 * 2 * pi;
    final targetAngle =
        _currentAngle + extraSpins + (2 * pi - (winnerAngle % (2 * pi)));

    _spinCtrl.duration = const Duration(seconds: 5);
    _spinAnim = Tween<double>(begin: _currentAngle, end: targetAngle).animate(
      CurvedAnimation(parent: _spinCtrl, curve: Curves.slowMiddle),
    );

    _spinCtrl.forward(from: 0).then((_) {
      _currentAngle = targetAngle;
      setState(() {
        _spinning = false;
      });
      HapticFeedback.vibrate();
      _showWinnerDialog(winner); // Hiển thị kết quả thắng cuộc công khai
    });
  }

  // 4. Lập đơn hàng quà tặng không đồng (Gộp đơn hoặc mở đơn quà riêng)
  Future<void> _createGiftOrder(String winnerName) async {
    try {
      // Tìm xem khách hàng này đã có đơn hàng chờ xử lý (DRAFT) nào ở phiên live này chưa
      final existingRes = await _db
          .from('orders')
          .select('id, notes')
          .eq('session_id', widget.session.id)
          .eq('customer_name', winnerName)
          .eq('status', 'DRAFT')
          .limit(1);

      if ((existingRes as List).isNotEmpty) {
        final orderId = existingRes[0]['id'] as String;
        final currentNotes = existingRes[0]['notes'] as String? ?? '';

        // ── TRƯỜNG HỢP 1: GỘP QUÀ VÀO ĐƠN SẴN CÓ ──
        await _db.from('order_details').insert({
          'order_id': orderId,
          'quantity': 1,
          'unit_price': 0,
        });

        // Bổ sung thông tin ghi chú dán chậu để đóng gói không bị sót quà
        final updatedNotes = currentNotes.isEmpty
            ? '🎁 TẶNG MINIGAME: $_giftName (0đ)'
            : '$currentNotes | 🎁 TẶNG MINIGAME: $_giftName (0đ)';

        await _db.from('orders').update({
          'notes': updatedNotes,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', orderId);

        _showSuccess(
            'Đã đính kèm quà tặng vào đơn hàng hiện tại của $winnerName ✓');
      } else {
        // ── TRƯỜNG HỢP 2: KHÁCH CHƯA MUA GÌ - TẠO ĐƠN FREE SHIP 0Đ RIÊNG ──
        await _db.from('orders').insert({
          'customer_name': winnerName,
          'session_id': widget.session.id,
          'platform': widget.session.platform,
          'source': 'livestream',
          'status': 'DRAFT',
          'shipping_fee': 0,
          'final_amount': 0,
          'notes': '🎁 ĐƠN QUÀ TRÚNG THƯỞNG: $_giftName (0đ)',
        });
        _showSuccess('Đã khởi tạo hóa đơn quà tặng 0đ cho $winnerName ✓');
      }
    } catch (e) {
      _showError('Không thể hoàn tất lập đơn quà: $e');
    }
  }

  void _showWinnerDialog(String winner) {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('🎉 Kết Quả Vòng Quay!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(
              winner,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF007AFF)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text('Chúc mừng đã trúng giải thưởng:\n$_giftName',
                textAlign: TextAlign.center),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Hủy bỏ'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.pop(context);
              _createGiftOrder(winner);
            },
            child: const Text('Xác nhận lập đơn'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.left_chevron, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${widget.session.platformEmoji} Vòng Quay May Mắn Realtime',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.settings, size: 18),
            onPressed: _editGiftName,
          )
        ],
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : Column(
              children: [
                // Thao trường hiển thị cấu trúc đồ họa vòng quay
                Expanded(
                  flex: 3,
                  child: Center(
                    child: _participants.isEmpty
                        ? _buildEmptyState()
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _WheelWidget(
                                participants: _participants,
                                animation:
                                    _spinCtrl.isAnimating ? _spinAnim : null,
                                currentAngle: _currentAngle,
                                onSpin: _spin,
                                spinning: _spinning,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Hệ thống đang đồng bộ liên tục ${_participants.length} thành viên...',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                    fontStyle: FontStyle.italic),
                              ),
                            ],
                          ),
                  ),
                ),
                // Phân mục khay hiển thị danh sách người dùng đang tương tác
                _buildParticipantList(),
              ],
            ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(CupertinoIcons.person_2_square_stack,
            size: 54, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        const Text('Chưa có dữ liệu tương tác...',
            style: TextStyle(
                fontWeight: FontWeight.w600, color: Colors.grey, fontSize: 14)),
        const SizedBox(height: 6),
        const Text(
            'Khách comment SĐT hoặc mã chốt trên Live sẽ tự động xuất hiện ở đây',
            style: TextStyle(fontSize: 11, color: Colors.grey),
            textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildParticipantList() {
    return Expanded(
      flex: 2,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('DANH SÁCH KHÁCH LIVE',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey,
                          letterSpacing: 0.8)),
                  Text('${_participants.length} thành viên',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF007AFF))),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _participants.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 11,
                    backgroundColor:
                        const Color(0xFF007AFF).withValues(alpha: 0.1),
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF007AFF))),
                  ),
                  title: Text(_participants[i],
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                  trailing: const Icon(CupertinoIcons.check_mark_circled,
                      size: 14, color: Color(0xFF34C759)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _editGiftName() {
    final ctrl = TextEditingController(text: _giftName);
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Cấu hình vật phẩm quà tặng'),
        content: Padding(
          padding: const EdgeInsets.only(
              top: 12), // Sửa lỗi thiết lập hàm .top thành .only thành công
          child: CupertinoTextField(
              controller: ctrl, placeholder: 'Nhập tên chậu cây tặng...'),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Hủy bỏ'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Lưu thông tin'),
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                setState(() => _giftName = ctrl.text.trim());
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFFFF3B30),
          behavior: SnackBarBehavior.floating),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFF34C759),
          behavior: SnackBarBehavior.floating),
    );
  }
}

// ------------------------------------------------------------
// COMPONENT VÒNG QUAY ĐỒ HỌA CUSTOM
// ------------------------------------------------------------

class _WheelWidget extends StatelessWidget {
  final List<String> participants;
  final Animation<double>? animation;
  final double currentAngle;
  final VoidCallback onSpin;
  final bool spinning;

  const _WheelWidget({
    required this.participants,
    this.animation,
    required this.currentAngle,
    required this.onSpin,
    required this.spinning,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: animation ?? const AlwaysStoppedAnimation(0),
          builder: (ctx, child) => Transform.rotate(
            angle: animation?.value ?? currentAngle,
            child: CustomPaint(
              size: const Size(280, 280),
              painter: _LuckyWheelPainter(participants),
            ),
          ),
        ),
        Positioned(
          top: -6,
          child: Icon(CupertinoIcons.triangle_fill,
              size: 28, color: const Color(0xFFFF3B30).withValues(alpha: 0.9)),
        ),
        GestureDetector(
          onTap: spinning ? null : onSpin,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Center(
              child: Text(
                spinning ? '...' : 'QUAY',
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: Color(0xFF1C1C1E)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LuckyWheelPainter extends CustomPainter {
  final List<String> names;
  final List<Color> colors = [
    const Color(0xFF007AFF),
    const Color(0xFF34C759),
    const Color(0xFFFF9F0A),
    const Color(0xFF5E5CE6),
    const Color(0xFFFF375F),
    const Color(0xFF30B0C7),
  ];

  _LuckyWheelPainter(this.names);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final angle = 2 * pi / names.length;

    for (var i = 0; i < names.length; i++) {
      final paint = Paint()..color = colors[i % colors.length];
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
          i * angle - pi / 2, angle, true, paint);

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(i * angle + angle / 2 - pi / 2);

      final textPainter = TextPainter(
        text: TextSpan(
          text:
              names[i].length > 8 ? '${names[i].substring(0, 7)}..' : names[i],
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, Offset(radius * 0.4, -textPainter.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

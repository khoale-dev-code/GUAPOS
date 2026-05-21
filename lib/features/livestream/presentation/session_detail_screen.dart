import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'create_order_sheet.dart';
import '../../../../shared/models/livestream_models.dart';

class SessionDetailScreen extends StatefulWidget {
  final LiveSession session;
  const SessionDetailScreen({super.key, required this.session});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _comments = [];

  // Filter: 'all' | 'done' | 'pending'
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _db
            .from('livestream_orders')
            .select(
                'id, customer_name, customer_phone, product_name, quantity, status, created_at, note')
            .eq('session_id', widget.session.id)
            .order('created_at', ascending: true),
        _db
            .from('livestream_comments')
            .select('id, commenter_name, comment_text, created_at')
            .eq('session_id', widget.session.id)
            .order('created_at', ascending: false),
      ]);
      _orders = List<Map<String, dynamic>>.from(results[0]);
      _comments = List<Map<String, dynamic>>.from(results[1]);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filteredOrders {
    if (_statusFilter == 'all') return _orders;
    return _orders.where((o) => o['status'] == _statusFilter).toList();
  }

  int get _doneCount => _orders.where((o) => o['status'] == 'done').length;

  // ── Export CSV via share sheet ──
  Future<void> _exportCsv() async {
    final buf = StringBuffer();
    buf.writeln('STT,Tên khách,SĐT,Sản phẩm,SL,Trạng thái,Ghi chú');
    for (var i = 0; i < _orders.length; i++) {
      final o = _orders[i];
      final status = o['status'] == 'done' ? 'Hoàn thành' : 'Chờ xử lý';
      buf.writeln('${i + 1},"${o['customer_name'] ?? ''}",'
          '"${o['customer_phone'] ?? ''}",'
          '"${o['product_name'] ?? ''}",'
          '${o['quantity'] ?? 1},'
          '$status,'
          '"${o['note'] ?? ''}"');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    _showSnack('Đã sao chép CSV vào clipboard');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final isTikTok = s.platform == 'tiktok';
    final platformColor =
        isTikTok ? const Color(0xFF1C1C1E) : const Color(0xFF1877F2);
    final platformBg =
        isTikTok ? const Color(0xFFF2F2F7) : const Color(0xFFE6F1FB);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: const Icon(CupertinoIcons.back, color: Color(0xFF007AFF)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: platformBg,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                isTikTok
                    ? CupertinoIcons.play_circle
                    : CupertinoIcons.video_camera,
                size: 14,
                color: platformColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            onPressed: _loading ? null : _exportCsv,
            child: const Icon(CupertinoIcons.share,
                size: 20, color: Color(0xFF007AFF)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : RefreshIndicator.adaptive(
              onRefresh: _fetchData,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  // ── SESSION INFO CARD ──
                  _SessionInfoCard(session: s, orders: _orders),
                  const SizedBox(height: 14),

                  // ── ORDER LIST ──
                  _OrderSection(
                    orders: _filteredOrders,
                    allOrders: _orders,
                    statusFilter: _statusFilter,
                    doneCount: _doneCount,
                    onFilterChanged: (f) => setState(() => _statusFilter = f),
                    onOrderTap: (order) async {
                      // Re-open as comment for edit
                      final comment = LiveComment(
                        id: order['id']?.toString() ?? '',
                        sessionId: s.id,
                        commenterName: order['customer_name'] as String? ?? '',
                        commentText: order['product_name'] as String? ?? '',
                        createdAt:
                            DateTime.parse(order['created_at'] as String),
                      );
                      await showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => CreateOrderSheet(
                          comment: comment,
                          session: s,
                        ),
                      );
                      _fetchData();
                    },
                    onStatusToggle: (order) async {
                      final newStatus =
                          order['status'] == 'done' ? 'pending' : 'done';
                      try {
                        await _db.from('livestream_orders').update(
                            {'status': newStatus}).eq('id', order['id']);
                        _fetchData();
                      } catch (_) {
                        _showSnack('Cập nhật thất bại, thử lại');
                      }
                    },
                  ),
                  const SizedBox(height: 14),

                  // ── COMMENT SECTION ──
                  _CommentSection(comments: _comments),
                  const SizedBox(height: 20),
                ],
              ),
            ),
      // ── EXPORT BOTTOM BAR ──
      bottomNavigationBar: _loading
          ? null
          : _ExportBar(
              onCopyCsv: _exportCsv,
              onPrint: () => sendPrompt(
                  'In danh sách đơn hàng phiên "${s.title}" ngày '
                  '${s.createdAt.day}/${s.createdAt.month}/${s.createdAt.year}'),
            ),
    );
  }

  // Helper to trigger AI action
  void sendPrompt(String msg) {
    _showSnack('Đang chuẩn bị in... (tích hợp trong app thật)');
  }
}

// ─────────────────────────────────────────────────────────────
// SESSION INFO CARD
// ─────────────────────────────────────────────────────────────

class _SessionInfoCard extends StatelessWidget {
  final LiveSession session;
  final List<Map<String, dynamic>> orders;

  const _SessionInfoCard({required this.session, required this.orders});

  @override
  Widget build(BuildContext context) {
    final isTikTok = session.platform == 'tiktok';
    final done = orders.where((o) => o['status'] == 'done').length;
    final total = orders.length;
    final d = session.createdAt.toLocal();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
      ),
      child: Column(
        children: [
          // Top: date & platform
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Icon(
                  isTikTok
                      ? CupertinoIcons.play_circle
                      : CupertinoIcons.video_camera,
                  size: 14,
                  color: isTikTok
                      ? const Color(0xFF1C1C1E)
                      : const Color(0xFF1877F2),
                ),
                const SizedBox(width: 6),
                Text(
                  isTikTok ? 'TikTok Live' : 'Facebook Live',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isTikTok
                        ? const Color(0xFF1C1C1E)
                        : const Color(0xFF1877F2),
                  ),
                ),
                const Spacer(),
                Text(
                  '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}'
                  '  ${d.hour}:${d.minute.toString().padLeft(2, '0')}',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          // KPIs
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Expanded(child: _MiniKpi(label: 'Tổng đơn', value: '$total')),
                _Divider(),
                Expanded(
                    child: _MiniKpi(
                        label: 'Hoàn thành',
                        value: '$done',
                        valueColor: const Color(0xFF34C759))),
                _Divider(),
                Expanded(
                    child: _MiniKpi(
                        label: 'Chờ xử lý',
                        value: '${total - done}',
                        valueColor: const Color(0xFFFF9F0A))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniKpi extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _MiniKpi({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? const Color(0xFF1C1C1E))),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
        ],
      );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 0.5, height: 36, color: const Color(0xFFE5E5EA));
}

// ─────────────────────────────────────────────────────────────
// ORDER SECTION
// ─────────────────────────────────────────────────────────────

class _OrderSection extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> allOrders;
  final String statusFilter;
  final int doneCount;
  final ValueChanged<String> onFilterChanged;
  final void Function(Map<String, dynamic>) onOrderTap;
  final void Function(Map<String, dynamic>) onStatusToggle;

  const _OrderSection({
    required this.orders,
    required this.allOrders,
    required this.statusFilter,
    required this.doneCount,
    required this.onFilterChanged,
    required this.onOrderTap,
    required this.onStatusToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          children: [
            const Text(
              'DANH SÁCH ĐƠN HÀNG',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8E8E93),
                  letterSpacing: 0.4),
            ),
            const Spacer(),
            _StatusFilterChip(
              label: 'Tất cả',
              count: allOrders.length,
              active: statusFilter == 'all',
              onTap: () => onFilterChanged('all'),
            ),
            const SizedBox(width: 5),
            _StatusFilterChip(
              label: 'Xong',
              count: doneCount,
              active: statusFilter == 'done',
              activeColor: const Color(0xFF34C759),
              onTap: () => onFilterChanged('done'),
            ),
            const SizedBox(width: 5),
            _StatusFilterChip(
              label: 'Chờ',
              count: allOrders.length - doneCount,
              active: statusFilter == 'pending',
              activeColor: const Color(0xFFFF9F0A),
              onTap: () => onFilterChanged('pending'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (orders.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
            ),
            child: const Center(
              child: Text('Không có đơn nào',
                  style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Divider(height: 1, color: Color(0xFFF0F0F0)),
              ),
              itemBuilder: (ctx, i) => _OrderRow(
                index: i + 1,
                order: orders[i],
                onTap: () => onOrderTap(orders[i]),
                onStatusToggle: () => onStatusToggle(orders[i]),
              ),
            ),
          ),
      ],
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _StatusFilterChip({
    required this.label,
    required this.count,
    required this.active,
    this.activeColor = const Color(0xFF1C1C1E),
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color:
              active ? activeColor.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? activeColor : const Color(0xFFE5E5EA),
            width: active ? 1 : 0.5,
          ),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: active ? activeColor : const Color(0xFF8E8E93),
          ),
        ),
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final int index;
  final Map<String, dynamic> order;
  final VoidCallback onTap;
  final VoidCallback onStatusToggle;

  const _OrderRow({
    required this.index,
    required this.order,
    required this.onTap,
    required this.onStatusToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = order['status'] == 'done';
    final name = order['customer_name'] as String? ?? 'Khách';
    final phone = order['customer_phone'] as String? ?? '';
    final product = order['product_name'] as String? ?? '';
    final qty = (order['quantity'] as int?) ?? 1;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            // Index
            SizedBox(
              width: 20,
              child: Text(
                '$index',
                style: const TextStyle(fontSize: 12, color: Color(0xFFC7C7CC)),
              ),
            ),
            const SizedBox(width: 8),
            // Customer info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1C1C1E))),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        Text(phone,
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF185FA5))),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$product  ×$qty',
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Status toggle
            GestureDetector(
              onTap: onStatusToggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDone
                      ? const Color(0xFFEAF3DE)
                      : const Color(0xFFFAEEDA),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  isDone ? 'Hoàn thành' : 'Chờ xử lý',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDone
                        ? const Color(0xFF27500A)
                        : const Color(0xFF633806),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// COMMENT SECTION
// ─────────────────────────────────────────────────────────────

class _CommentSection extends StatelessWidget {
  final List<Map<String, dynamic>> comments;
  const _CommentSection({required this.comments});

  @override
  Widget build(BuildContext context) {
    if (comments.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'BÌNH LUẬN TRONG PHIÊN',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8E8E93),
              letterSpacing: 0.4),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: comments.length > 20 ? 20 : comments.length,
            separatorBuilder: (_, __) => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Divider(height: 1, color: Color(0xFFF0F0F0)),
            ),
            itemBuilder: (ctx, i) {
              final c = comments[i];
              final name = c['commenter_name'] as String? ?? 'Khách ẩn danh';
              final text = c['comment_text'] as String? ?? '';
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF185FA5)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF3C3C43)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (comments.length > 20)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              '... và ${comments.length - 20} bình luận khác',
              style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// EXPORT BOTTOM BAR
// ─────────────────────────────────────────────────────────────

class _ExportBar extends StatelessWidget {
  final VoidCallback onCopyCsv;
  final VoidCallback onPrint;

  const _ExportBar({required this.onCopyCsv, required this.onPrint});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(14, 12, 14, 12 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E5EA), width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ExportButton(
              icon: CupertinoIcons.doc_text,
              label: 'Copy CSV',
              onTap: onCopyCsv,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ExportButton(
              icon: CupertinoIcons.printer,
              label: 'In đơn hàng',
              onTap: onPrint,
              primary: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  const _ExportButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: primary ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: primary ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: primary ? Colors.white : const Color(0xFF3C3C43)),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: primary ? Colors.white : const Color(0xFF3C3C43),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

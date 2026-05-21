import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../data/order_models.dart';
import '../data/orders_repository.dart';
import 'order_detail_screen.dart';
import 'create_manual_order_sheet.dart';

// ─── Palette nhà vườn ────────────────────────────────────────
const _kGreen = Color(0xFF34C759);
const _kBlue = Color(0xFF007AFF);
const _kOrange = Color(0xFFFF9F0A);
const _kRed = Color(0xFFFF3B30);
const _kBg = Color(0xFFF2F2F7);

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _repo = OrdersRepository();

  List<Order> _orders = [];
  bool _loading = true;
  String _statusFilter = 'DRAFT';
  bool _selectMode = false;
  final Set<String> _selected = {};

  static const _statusTabs = [
    ('DRAFT', '🌱 Chờ chốt'),
    ('CONFIRMED', '✅ Đã chốt'),
    ('SHIPPING', '🚚 Giao hàng'),
    ('DONE', '🏆 Hoàn thành'),
    ('CANCELLED', '❌ Đã huỷ'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _selected.clear();
      _selectMode = false;
    });
    try {
      final orders = await _repo.getOrders(status: _statusFilter);
      if (mounted) setState(() => _orders = orders);
    } catch (e) {
      _showError('Lỗi tải đơn: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Chốt đơn hàng'),
        content: Text('Xác nhận chốt $count đơn đã chọn?'),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Huỷ')),
          CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Chốt ngay')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _loading = true);
    try {
      await _repo.confirmMany(_selected.toList());
      if (mounted) _showSuccess('Đã chốt $count đơn ✓');
      _load();
    } catch (e) {
      _showError('Lỗi: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleSelect(String id) => setState(() {
        _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
        if (_selected.isEmpty) _selectMode = false;
      });

  void _selectAll() => setState(() {
        if (_selected.length == _orders.length) {
          _selected.clear();
          _selectMode = false;
        } else {
          _selected.addAll(_orders.map((o) => o.id));
        }
      });

  void _showError(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating));
  }

  void _showSuccess(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: _kGreen,
        behavior: SnackBarBehavior.floating));
  }

  void _openDetail(Order order) => Navigator.push(context,
          CupertinoPageRoute(builder: (_) => OrderDetailScreen(order: order)))
      .then((_) => _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: _buildAppBar(),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : _orders.isEmpty
              ? _EmptyOrders(status: _statusFilter)
              : RefreshIndicator.adaptive(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: _orders.length,
                    itemBuilder: (ctx, i) => _OrderCard(
                      order: _orders[i],
                      selectMode: _selectMode,
                      selected: _selected.contains(_orders[i].id),
                      onTap: _selectMode
                          ? () => _toggleSelect(_orders[i].id)
                          : () => _openDetail(_orders[i]),
                      onLongPress: () {
                        if (!_selectMode && _statusFilter == 'DRAFT') {
                          setState(() {
                            _selectMode = true;
                            _selected.add(_orders[i].id);
                          });
                        }
                      },
                    ),
                  ),
                ),
      floatingActionButton: !_selectMode ? _buildFAB() : null,
      bottomNavigationBar: (_selectMode && _selected.isNotEmpty)
          ? _BulkActionBar(count: _selected.length, onConfirm: _confirmSelected)
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
        backgroundColor: _kBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 20,
        title: _selectMode
            ? Text('${_selected.length} đơn được chọn',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))
            : const Text('Đơn hàng',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5)),
        actions: [
          if (_selectMode) ...[
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              onPressed: _selectAll,
              child: Text(
                  _selected.length == _orders.length
                      ? 'Bỏ chọn tất cả'
                      : 'Chọn tất cả',
                  style: const TextStyle(
                      fontSize: 14,
                      color: _kBlue,
                      fontWeight: FontWeight.w600)),
            ),
            CupertinoButton(
              padding: const EdgeInsets.only(right: 12),
              onPressed: () => setState(() {
                _selectMode = false;
                _selected.clear();
              }),
              child: const Text('Huỷ',
                  style: TextStyle(
                      fontSize: 14, color: _kRed, fontWeight: FontWeight.w600)),
            ),
          ] else ...[
            if (_statusFilter == 'DRAFT' && _orders.isNotEmpty)
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: () => setState(() => _selectMode = true),
                child: const Text('Chọn',
                    style: TextStyle(
                        fontSize: 14,
                        color: _kBlue,
                        fontWeight: FontWeight.w600)),
              ),
            IconButton(
                onPressed: _load,
                icon: const Icon(CupertinoIcons.refresh, size: 20)),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: _StatusTabBar(
            selected: _statusFilter,
            onChanged: (s) {
              setState(() => _statusFilter = s);
              _load();
            },
            tabs: _statusTabs,
            count: _orders.length,
          ),
        ),
      );

  Widget _buildFAB() => Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color.fromARGB(255, 12, 105, 35),
              Color.fromARGB(255, 2, 111, 27)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
                color: _kBlue.withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () async {
            final ok = await showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const CreateManualOrderSheet(),
            );
            if (ok == true) _load();
          },
          backgroundColor: const Color.fromARGB(0, 9, 135, 28),
          elevation: 0,
          icon: const Icon(CupertinoIcons.add, color: Colors.white, size: 18),
          label: const Text('Tạo đơn',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
        ),
      );
}

// ── Tab bar trạng thái ───────────────────────────────────────
class _StatusTabBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  final List<(String, String)> tabs;
  final int count;

  const _StatusTabBar(
      {required this.selected,
      required this.onChanged,
      required this.tabs,
      required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: tabs.length,
        itemBuilder: (ctx, i) {
          final (code, label) = tabs[i];
          final active = selected == code;
          return GestureDetector(
            onTap: () => onChanged(code),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: active ? _kBlue : Colors.transparent,
                        width: 2.5)),
              ),
              child: Center(
                  child: Row(children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? _kBlue : Colors.grey.shade500)),
                if (active && count > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                        color: _kBlue, borderRadius: BorderRadius.circular(8)),
                    child: Text('$count',
                        style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ])),
            ),
          );
        },
      ),
    );
  }
}

// ── Order Card ───────────────────────────────────────────────
class _OrderCard extends StatelessWidget {
  final Order order;
  final bool selectMode, selected;
  final VoidCallback onTap, onLongPress;

  const _OrderCard(
      {required this.order,
      required this.selectMode,
      required this.selected,
      required this.onTap,
      required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final code =
        order.orderCode ?? '#${order.id.substring(0, 8).toUpperCase()}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? _kBlue : Colors.transparent, width: 2),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Column(children: [
              // ── Header bar ──────────────────────────────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: order.statusColor.withOpacity(0.06),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(children: [
                  if (selectMode) ...[
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        selected
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.circle,
                        key: ValueKey(selected),
                        size: 20,
                        color: selected ? _kBlue : Colors.grey.shade400,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(order.platformEmoji,
                      style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(code,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: Color(0xFF3C3C43))),
                  const Spacer(),
                  _StatusPill(status: order.status),
                ]),
              ),

              // ── Body ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar khách
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: [
                                _avatarColor(order.customerName)
                                    .withOpacity(0.7),
                                _avatarColor(order.customerName)
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                            child: Text(
                          (order.customerName?.isNotEmpty == true)
                              ? order.customerName![0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800),
                        )),
                      ),
                      const SizedBox(width: 12),

                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(order.customerName ?? 'Khách hàng',
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Row(children: [
                            Icon(CupertinoIcons.phone_fill,
                                size: 11, color: Colors.grey.shade400),
                            const SizedBox(width: 4),
                            Text(order.phone ?? 'Chưa có SĐT',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: order.phone != null
                                        ? const Color(0xFF007AFF)
                                        : Colors.red.shade400,
                                    fontWeight: FontWeight.w600)),
                          ]),
                          if (order.items.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('🌱',
                                        style: TextStyle(fontSize: 10)),
                                    const SizedBox(width: 4),
                                    Flexible(
                                        child: Text(
                                      order.items
                                          .map((i) => i.productName)
                                          .join(' · '),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.green.shade800,
                                          fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    )),
                                  ]),
                            ),
                          ],
                        ],
                      )),

                      const SizedBox(width: 10),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Text(_fmt(order.finalAmount ?? 0),
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: _kRed,
                                    letterSpacing: -0.3)),
                            const SizedBox(height: 3),
                            Text(_fmtTime(order.createdAt),
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade400)),
                          ]),
                    ]),
              ),

              // ── Quick actions ────────────────────────────
              if (!selectMode) ...[
                const SizedBox(height: 10),
                Divider(height: 1, color: Colors.grey.shade100),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _QuickBtn(
                          icon: CupertinoIcons.phone_fill,
                          label: 'Gọi',
                          color: _kGreen,
                          onTap: () {}),
                      _Vline(),
                      _QuickBtn(
                          icon: CupertinoIcons.doc_on_clipboard,
                          label: 'Copy SĐT',
                          color: _kBlue,
                          onTap: () {}),
                      _Vline(),
                      _QuickBtn(
                          icon: CupertinoIcons.printer_fill,
                          label: 'In phiếu',
                          color: _kOrange,
                          onTap: () {}),
                    ],
                  ),
                ),
              ] else
                const SizedBox(height: 10),
            ]),
          ),
        ),
      ),
    );
  }

  Color _avatarColor(String? name) {
    final colors = [
      const Color(0xFF5E5CE6),
      const Color(0xFF30B0C7),
      const Color(0xFFFF9F0A),
      const Color(0xFF34C759),
      const Color(0xFFFF375F),
      const Color(0xFF007AFF),
    ];
    if (name == null || name.isEmpty) return colors[0];
    return colors[name.codeUnitAt(0) % colors.length];
  }

  String _fmt(double v) =>
      '${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} đ';

  String _fmtTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    return '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _Vline extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(height: 22, width: 1, color: Colors.grey.shade100);
}

class _QuickBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13),
          const SizedBox(width: 5),
          Text(label,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

// ── Status Pill ──────────────────────────────────────────────
class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final order = Order(id: '', status: status, createdAt: DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: order.statusColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(order.statusLabel,
          style: const TextStyle(
              fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
    );
  }
}

// ── Bulk Action Bar ──────────────────────────────────────────
class _BulkActionBar extends StatelessWidget {
  final int count;
  final VoidCallback onConfirm;

  const _BulkActionBar({required this.count, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    // 🚀 Bọc thêm Column(mainAxisSize: MainAxisSize.min) ở đây
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5))
              ],
            ),
            child: FilledButton.icon(
              onPressed: onConfirm,
              icon: const Icon(CupertinoIcons.checkmark_alt_circle_fill,
                  size: 20),
              label: Text(
                'Chốt nhanh $count đơn',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Empty State ──────────────────────────────────────────────
class _EmptyOrders extends StatelessWidget {
  final String status;
  const _EmptyOrders({required this.status});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                  color: Colors.green.shade50, shape: BoxShape.circle),
              child: const Center(
                  child: Text('🌿', style: TextStyle(fontSize: 40)))),
          const SizedBox(height: 16),
          Text(status == 'DRAFT' ? 'Chưa có đơn chờ chốt' : 'Chưa có đơn nào',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3)),
          const SizedBox(height: 8),
          Text('Đơn từ livestream sẽ tự xuất hiện ở đây',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
        ]),
      );
}

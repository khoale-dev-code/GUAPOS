import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/order_models.dart';
import '../data/orders_repository.dart';

const _kGreen = Color(0xFF34C759);
const _kBlue = Color(0xFF007AFF);
const _kOrange = Color(0xFFFF9F0A);
const _kRed = Color(0xFFFF3B30);
const _kBg = Color(0xFFF2F2F7);
const _kPurple = Color(0xFF5E5CE6);

class OrderDetailScreen extends StatefulWidget {
  final Order order;
  const OrderDetailScreen({super.key, required this.order});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _repo = OrdersRepository();
  final _db = Supabase.instance.client;
  late Order _order;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  // ── 🔄 Reload dữ liệu từ Database ───────────────────────
  Future<void> _reloadOrder() async {
    try {
      final res = await _db.from('orders').select('''
            id, order_code, customer_name, phone, status,
            final_amount, shipping_fee, notes, platform,
            session_id, created_at, updated_at,
            order_details(
              id, order_id, variant_id, quantity, unit_price, total_price,
              product_variants(variant_name, products(product_name))
            )
          ''').eq('id', _order.id).single();
      if (mounted) setState(() => _order = Order.fromJson(res));
    } catch (e) {
      _showError('Lỗi tải lại đơn: $e');
    }
  }

  // ── Sửa Đơn: Thêm Sản Phẩm ─────────────────────────────
  Future<void> _showAddProductPicker() async {
    setState(() => _loading = true);
    try {
      final res = await _db
          .from('product_variants')
          .select(
              'id, variant_name, base_price, stock_quantity, products(product_name)')
          .eq('is_active', true)
          .gt('stock_quantity', 0)
          .order('variant_name');
      final products = List<Map<String, dynamic>>.from(res);

      if (!mounted) return;
      setState(() => _loading = false);

      final selectedProduct = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: _ProductPickerModal(products: products),
        ),
      );

      if (selectedProduct != null) {
        _showConfigNewItemDialog(selectedProduct);
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _showError('Lỗi tải kho: $e');
    }
  }

  void _showConfigNewItemDialog(Map<String, dynamic> product) {
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController(
        text: (product['base_price'] as num?)?.toInt().toString() ?? '0');

    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Thêm vào đơn'),
        content: Column(
          children: [
            const SizedBox(height: 8),
            Text('🌱 ${product['variant_name']}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            CupertinoTextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                prefix: const Padding(
                    padding: EdgeInsets.only(left: 8), child: Text('SL: '))),
            const SizedBox(height: 8),
            CupertinoTextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                prefix: const Padding(
                    padding: EdgeInsets.only(left: 8), child: Text('Giá: '))),
          ],
        ),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Huỷ')),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _loading = true);
              try {
                await _db.from('order_details').insert({
                  'order_id': _order.id,
                  'variant_id': product['id'],
                  'quantity': int.parse(qtyCtrl.text),
                  'unit_price': double.parse(priceCtrl.text),
                  // KHÔNG thêm total_price vì là Generated Column
                });
                await _db.from('orders').update({
                  'updated_at': DateTime.now().toIso8601String()
                }).eq('id', _order.id);
                await _reloadOrder();
                _showSuccess('Đã thêm sản phẩm ✓');
              } catch (e) {
                _showError('Lỗi thêm: $e');
              } finally {
                if (mounted) setState(() => _loading = false);
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  // ── Sửa Đơn: Chỉnh Sửa Sản Phẩm (Số lượng / Giá) ────────
  void _editItem(OrderItem item) {
    final qtyCtrl = TextEditingController(text: item.quantity.toString());
    final priceCtrl =
        TextEditingController(text: item.unitPrice.toInt().toString());

    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Cập nhật sản phẩm'),
        content: Column(
          children: [
            const SizedBox(height: 8),
            Text('🌱 ${item.productName}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            CupertinoTextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                prefix: const Padding(
                    padding: EdgeInsets.only(left: 8), child: Text('SL: '))),
            const SizedBox(height: 8),
            CupertinoTextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                prefix: const Padding(
                    padding: EdgeInsets.only(left: 8), child: Text('Giá: '))),
          ],
        ),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Huỷ')),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _loading = true);
              try {
                await _db.from('order_details').update({
                  'quantity': int.parse(qtyCtrl.text),
                  'unit_price': double.parse(priceCtrl.text),
                }).eq('id', item.id);
                await _db.from('orders').update({
                  'updated_at': DateTime.now().toIso8601String()
                }).eq('id', _order.id);
                await _reloadOrder(); // Tải lại để DB tự tính tổng
                _showSuccess('Đã cập nhật ✓');
              } catch (e) {
                _showError('Lỗi cập nhật: $e');
              } finally {
                if (mounted) setState(() => _loading = false);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  // ── Sửa Đơn: Xoá Sản Phẩm ─────────────────────────────
  Future<void> _deleteItem(OrderItem item) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Xoá sản phẩm?'),
        content: Text('Xoá "${item.productName}" khỏi đơn?'),
        actions: [
          CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Xoá')),
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Giữ lại')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _loading = true);
    try {
      await _repo.deleteItem(item.id, _order.id);
      await _reloadOrder(); // Tải lại để lấy tổng tiền mới
      _showSuccess('Đã xoá ✓');
    } catch (e) {
      _showError('Lỗi: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeStatus(String newStatus) async {
    final labels = {
      'CONFIRMED': 'Xác nhận chốt đơn?',
      'SHIPPING': 'Chuyển sang Đang giao?',
      'DONE': 'Đánh dấu Hoàn thành?',
      'CANCELLED': 'Huỷ đơn hàng này?',
    };
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(labels[newStatus] ?? 'Đổi trạng thái?'),
        actions: [
          CupertinoDialogAction(
              isDestructiveAction: newStatus == 'CANCELLED',
              onPressed: () => Navigator.pop(context, true),
              child: Text(newStatus == 'CANCELLED' ? 'Huỷ đơn' : 'Xác nhận')),
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Không')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _loading = true);
    try {
      await _repo.updateStatus(_order.id, newStatus);
      await _reloadOrder();
      _showSuccess('Cập nhật thành công ✓');
    } catch (e) {
      _showError('Lỗi: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _editNotes() {
    final ctrl = TextEditingController(text: _order.notes ?? '');
    final shipCtrl = TextEditingController(
        text: _order.shippingFee?.toInt().toString() ?? '40000');

    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Địa chỉ & Phí ship'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            children: [
              CupertinoTextField(
                  controller: shipCtrl,
                  placeholder: 'Phí ship (đ)',
                  keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              CupertinoTextField(
                  controller: ctrl,
                  placeholder: 'Địa chỉ giao hàng, ghi chú...',
                  maxLines: 3),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Huỷ')),
          CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () async {
                Navigator.pop(context);
                setState(() => _loading = true);
                try {
                  await _repo.updateOrder(_order.id,
                      notes: ctrl.text.trim(),
                      shippingFee: double.tryParse(shipCtrl.text) ?? 0);
                  await _reloadOrder();
                  _showSuccess('Đã lưu thông tin ✓');
                } catch (e) {
                  _showError('Lỗi cập nhật: $e');
                } finally {
                  if (mounted) setState(() => _loading = false);
                }
              },
              child: const Text('Lưu')),
        ],
      ),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final canEdit = _order.status == 'DRAFT';
    final subtotal = _order.subtotal;
    final ship = _order.shippingFee ?? 40000;
    final total = subtotal + ship;
    final code =
        _order.orderCode ?? '#${_order.id.substring(0, 8).toUpperCase()}';

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(CupertinoIcons.chevron_left, size: 20)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(code,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3)),
          Text(_fmtFull(_order.createdAt),
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w400)),
        ]),
        actions: [
          IconButton(
              onPressed: () {},
              icon:
                  const Icon(CupertinoIcons.printer, size: 20, color: _kBlue)),
        ],
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusBanner(order: _order),
                  const SizedBox(height: 16),

                  // ── Thông tin khách & Địa chỉ ──────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const _SectionLabel(label: 'Khách hàng & Giao hàng'),
                      if (canEdit)
                        GestureDetector(
                          onTap: _editNotes,
                          child: const Icon(CupertinoIcons.pencil_circle_fill,
                              color: _kBlue, size: 22),
                        )
                    ],
                  ),
                  _Card(
                      child: Column(children: [
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  colors: [_kBlue.withOpacity(0.7), _kBlue]),
                              shape: BoxShape.circle),
                          child: Center(
                              child: Text(
                                  (_order.customerName?.isNotEmpty == true)
                                      ? _order.customerName![0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800))),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_order.customerName ?? 'Khách hàng ẩn danh',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 3),
                            Text(_order.phone ?? 'Chưa có SĐT',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: _order.phone != null
                                        ? _kBlue
                                        : Colors.red.shade400,
                                    fontWeight: FontWeight.w600)),
                          ],
                        )),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                              color: _kGreen.withOpacity(0.1),
                              shape: BoxShape.circle),
                          child: const Icon(CupertinoIcons.phone_fill,
                              size: 18, color: _kGreen),
                        ),
                      ]),
                    ),
                    Divider(height: 1, color: Colors.grey.shade100),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                              color: _kOrange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8)),
                          child: const Icon(CupertinoIcons.location_solid,
                              size: 16, color: _kOrange),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Địa chỉ giao hàng',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 3),
                            Text(
                              (_order.notes?.isNotEmpty == true)
                                  ? _order.notes!
                                  : 'Chưa cập nhật — nhấn biểu tượng bút để sửa',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: (_order.notes?.isNotEmpty == true)
                                      ? const Color(0xFF1C1C1E)
                                      : Colors.orange.shade600,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        )),
                      ]),
                    ),
                  ])),
                  const SizedBox(height: 16),

                  // ── Sản phẩm ────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SectionLabel(
                          label: '🌱 Sản phẩm (${_order.items.length})'),
                      if (canEdit)
                        TextButton.icon(
                          onPressed: _showAddProductPicker,
                          icon: const Icon(CupertinoIcons.add_circled_solid,
                              size: 18, color: _kGreen),
                          label: const Text('Thêm cây',
                              style: TextStyle(
                                  color: _kGreen, fontWeight: FontWeight.w700)),
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        )
                    ],
                  ),
                  ..._order.items.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ItemCard(
                            item: item,
                            canEdit: canEdit,
                            onEdit: () => _editItem(item),
                            canDelete: canEdit && _order.items.length > 1,
                            onDelete: () => _deleteItem(item)),
                      )),
                  const SizedBox(height: 16),

                  // ── Tổng tiền ────────────────────────────
                  const _SectionLabel(label: 'Thanh toán'),
                  _TotalCard(subtotal: subtotal, ship: ship, total: total),
                  const SizedBox(height: 8),
                ],
              ),
            ),
      // ── TÌM ĐẾN PHẦN NÀY Ở GẦN CUỐI HÀM BUILD VÀ SỬA LẠI ──
      bottomNavigationBar: _loading
          ? null
          : Column(
              mainAxisSize: MainAxisSize
                  .min, // 🚀 KEY FIX: Ép chiều cao tối thiểu để không bị lỗi SnackBar
              children: [
                SafeArea(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(color: Colors.white, boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 16,
                          offset: const Offset(0, -4))
                    ]),
                    child: _ActionButtons(
                        order: _order, onChangeStatus: _changeStatus),
                  ),
                ),
              ],
            ),
    );
  }

  String _fmtFull(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year} lúc ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
}

// ── Các Components UI Giữ Nguyên (Đã tối ưu) ──────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade500,
                letterSpacing: 0.6)),
      );
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ]),
        child: child,
      );
}

class _StatusBanner extends StatelessWidget {
  final Order order;
  const _StatusBanner({required this.order});

  static const _steps = ['DRAFT', 'CONFIRMED', 'SHIPPING', 'DONE'];
  static const _stepLabels = ['Chờ chốt', 'Đã chốt', 'Đang giao', 'Hoàn thành'];
  static const _stepEmojis = ['🌱', '✅', '🚚', '🏆'];

  @override
  Widget build(BuildContext context) {
    if (order.status == 'CANCELLED') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            color: _kRed.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kRed.withOpacity(0.25))),
        child: const Row(children: [
          Text('❌', style: TextStyle(fontSize: 22)),
          SizedBox(width: 12),
          Text('Đơn hàng đã bị huỷ',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: _kRed)),
        ]),
      );
    }
    final currentIdx = _steps.indexOf(order.status).clamp(0, 3);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ]),
      child: Column(children: [
        Row(
            children: List.generate(_steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            final filled = (i ~/ 2) < currentIdx;
            return Expanded(
                child: Container(
                    height: 3, color: filled ? _kGreen : Colors.grey.shade200));
          }
          final idx = i ~/ 2;
          final done = idx < currentIdx;
          final active = idx == currentIdx;
          return Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: active ? 34 : 28,
              height: active ? 34 : 28,
              decoration: BoxDecoration(
                color: done
                    ? _kGreen
                    : active
                        ? order.statusColor
                        : Colors.grey.shade100,
                shape: BoxShape.circle,
                boxShadow: active
                    ? [
                        BoxShadow(
                            color: order.statusColor.withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2))
                      ]
                    : [],
              ),
              child: Center(
                  child: Text(_stepEmojis[idx],
                      style: TextStyle(fontSize: active ? 16 : 13))),
            ),
          ]);
        })),
        const SizedBox(height: 8),
        Row(
            children: List.generate(_steps.length, (idx) {
          final active = idx == currentIdx;
          return Expanded(
              child: Text(_stepLabels[idx],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color:
                          active ? order.statusColor : Colors.grey.shade400)));
        })),
      ]),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final OrderItem item;
  final bool canEdit;
  final VoidCallback onEdit;
  final bool canDelete;
  final VoidCallback onDelete;

  const _ItemCard(
      {required this.item,
      required this.canEdit,
      required this.onEdit,
      required this.canDelete,
      required this.onDelete});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ]),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12)),
            child:
                const Center(child: Text('🌱', style: TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.productName,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text('${_fmt(item.unitPrice)} × ${item.quantity}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          )),
          Text(_fmt(item.totalPrice),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C1C1E))),
          if (canEdit) ...[
            const SizedBox(width: 12),
            Column(
              children: [
                GestureDetector(
                  onTap: onEdit,
                  child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: _kBlue.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Icon(CupertinoIcons.pencil,
                          size: 14, color: _kBlue)),
                ),
                if (canDelete) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: onDelete,
                    child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            color: _kRed.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Icon(CupertinoIcons.trash_fill,
                            size: 14, color: _kRed)),
                  ),
                ]
              ],
            )
          ],
        ]),
      );

  static String _fmt(double v) =>
      '${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} đ';
}

class _TotalCard extends StatelessWidget {
  final double subtotal, ship, total;
  const _TotalCard(
      {required this.subtotal, required this.ship, required this.total});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ]),
        child: Column(children: [
          _Row(label: '💰 Tiền hàng', value: _fmt(subtotal)),
          Divider(height: 1, indent: 16, color: Colors.grey.shade100),
          _Row(label: '🚚 Phí giao hàng', value: _fmt(ship)),
          Divider(height: 1, color: Colors.grey.shade200),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Row(children: [
              const Text('🏷️  Khách cần trả',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: _kRed.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10)),
                child: Text(_fmt(total),
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: _kRed,
                        letterSpacing: -0.5)),
              ),
            ]),
          ),
        ]),
      );

  static String _fmt(double v) =>
      '${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} đ';
}

class _Row extends StatelessWidget {
  final String label, value;
  const _Row({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(children: [
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))
        ]),
      );
}

class _ActionButtons extends StatelessWidget {
  final Order order;
  final ValueChanged<String> onChangeStatus;
  const _ActionButtons({required this.order, required this.onChangeStatus});

  @override
  Widget build(BuildContext context) {
    switch (order.status) {
      case 'DRAFT':
        return Row(children: [
          SizedBox(
            width: 100,
            child: OutlinedButton(
              onPressed: () => onChangeStatus('CANCELLED'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: _kRed,
                  side: BorderSide(color: _kRed.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: const Text('Huỷ đơn',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Container(
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF34C759), Color(0xFF007AFF)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: _kBlue.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ]),
            child: FilledButton.icon(
              onPressed: () => onChangeStatus('CONFIRMED'),
              icon: const Icon(CupertinoIcons.checkmark_seal_fill, size: 18),
              label: const Text('Chốt đơn ngay 🌸',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            ),
          )),
        ]);

      case 'CONFIRMED':
        return FilledButton.icon(
          onPressed: () => onChangeStatus('SHIPPING'),
          icon: const Icon(CupertinoIcons.cube_box_fill, size: 18),
          label: const Text('Chuyển Đang giao 🚚',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          style: FilledButton.styleFrom(
              backgroundColor: _kPurple,
              padding: const EdgeInsets.symmetric(vertical: 14),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
        );

      case 'SHIPPING':
        return FilledButton.icon(
          onPressed: () => onChangeStatus('DONE'),
          icon: const Icon(CupertinoIcons.money_dollar_circle_fill, size: 18),
          label: const Text('Đã giao – Thu tiền 🏆',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          style: FilledButton.styleFrom(
              backgroundColor: _kGreen,
              padding: const EdgeInsets.symmetric(vertical: 14),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
        );

      default:
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12)),
          child: const Center(
              child: Text('Đơn hàng đã kết thúc',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Colors.grey))),
        );
    }
  }
}

// ── Modal Chọn Sản Phẩm Mới ──────────────────────────────────────
class _ProductPickerModal extends StatefulWidget {
  final List<Map<String, dynamic>> products;
  const _ProductPickerModal({required this.products});
  @override
  State<_ProductPickerModal> createState() => _ProductPickerModalState();
}

class _ProductPickerModalState extends State<_ProductPickerModal> {
  String _search = '';
  List<Map<String, dynamic>> get _filtered => _search.isEmpty
      ? widget.products
      : widget.products
          .where((p) => ((p['variant_name'] ?? '') as String)
              .toLowerCase()
              .contains(_search.toLowerCase()))
          .toList();

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        Padding(
            padding: const EdgeInsets.all(14),
            child: CupertinoSearchTextField(
                placeholder: 'Tìm tên cây...',
                onChanged: (v) => setState(() => _search = v))),
        Expanded(
            child: ListView.separated(
          itemCount: _filtered.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, indent: 16, color: Colors.grey.shade100),
          itemBuilder: (ctx, i) {
            final p = _filtered[i];
            final price = (p['base_price'] as num?)?.toDouble() ?? 0;
            return ListTile(
              leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Center(
                      child: Text('🌱', style: TextStyle(fontSize: 20)))),
              title: Text(p['variant_name'] as String? ?? '',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              subtitle: Text('Tồn: ${p['stock_quantity']} cây',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: _kBlue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8)),
                child: Text('${price.toStringAsFixed(0)}đ',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _kBlue)),
              ),
              onTap: () => Navigator.pop(context, p),
            );
          },
        )),
      ]);
}

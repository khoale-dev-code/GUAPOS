import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _kGreen = Color(0xFF34C759);
const _kBlue = Color(0xFF007AFF);
const _kRed = Color(0xFFFF3B30);
const _kBg = Color(0xFFF2F2F7);

class CreateManualOrderSheet extends StatefulWidget {
  const CreateManualOrderSheet({super.key});
  @override
  State<CreateManualOrderSheet> createState() => _CreateManualOrderSheetState();
}

class _CreateManualOrderSheetState extends State<CreateManualOrderSheet> {
  final _db = Supabase.instance.client;

  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _productNameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _shipCtrl = TextEditingController(text: '40000');

  bool _loading = false;
  bool _findingExist = false;
  bool _isLoyalCustomer = false; // ✅ Cờ nhận diện khách quen
  Map<String, dynamic>? _existingOrder;
  Map<String, dynamic>? _selectedProduct;
  List<Map<String, dynamic>> _products = [];
  String _productMode = 'existing';
  String _selectedPlatform = 'zalo';

  static const _platforms = [
    ('zalo', '💬', 'Zalo'),
    ('store', '🏪', 'Tại vườn'),
    ('facebook', '📘', 'FB Mess'),
  ];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    _productNameCtrl.dispose();
    _priceCtrl.dispose();
    _shipCtrl.dispose();
    super.dispose();
  }

  // 🚀 NÂNG CẤP: Tra cứu toàn diện (Đơn nháp + Thông tin khách quen + Địa chỉ cũ)
  Future<void> _lookupCustomerData(String phone) async {
    setState(() {
      _findingExist = true;
      _isLoyalCustomer = false;
    });

    try {
      // 1. Tìm đơn DRAFT để gộp (như cũ)
      final draftRes = await _db
          .from('orders')
          .select('id, order_code, status')
          .eq('phone', phone)
          .eq('status', 'DRAFT')
          .isFilter('session_id', null)
          .limit(1);
      _existingOrder = (draftRes as List).isNotEmpty ? draftRes[0] : null;

      // 2. Quét bảng customers tìm khách quen
      final custRes = await _db
          .from('customers')
          .select('id, full_name')
          .eq('phone', phone)
          .limit(1);

      if ((custRes as List).isNotEmpty) {
        _isLoyalCustomer = true;
        final custName = custRes[0]['full_name'] as String?;

        // Tự động điền Tên nếu đang trống
        if (_nameCtrl.text.isEmpty && custName != null) {
          _nameCtrl.text = custName;
        }

        // 3. Quét đơn hàng cũ nhất có chứa Địa chỉ/Ghi chú để tự điền
        final lastOrderRes = await _db
            .from('orders')
            .select('notes')
            .eq('phone', phone)
            .not('notes', 'is', null) // Lấy đơn có ghi chú
            .order('created_at', ascending: false)
            .limit(1);

        if ((lastOrderRes as List).isNotEmpty) {
          final oldAddress = lastOrderRes[0]['notes'] as String?;
          if (_noteCtrl.text.isEmpty && oldAddress != null) {
            _noteCtrl.text = oldAddress;
          }
        }
      }
    } catch (_) {
    } finally {
      setState(() => _findingExist = false);
    }
  }

  Future<void> _loadProducts() async {
    try {
      final res = await _db
          .from('product_variants')
          .select(
              'id, variant_name, base_price, stock_quantity, products(product_name)')
          .eq('is_active', true)
          .gt('stock_quantity', 0)
          .order('variant_name');
      setState(() => _products = List<Map<String, dynamic>>.from(res));
    } catch (_) {}
  }

  String _generateSku(String name) {
    final ts = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    final prefix = name.trim().isEmpty
        ? 'SP'
        : name
            .trim()
            .substring(0, name.trim().length.clamp(0, 3))
            .toUpperCase();
    return '$prefix-$ts';
  }

  Future<void> _submit({required bool merge}) async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      _showError('Vui lòng nhập SĐT');
      return;
    }
    if (_productMode == 'existing' && _selectedProduct == null) {
      _showError('Vui lòng chọn cây');
      return;
    }
    if (_productMode == 'manual' && _productNameCtrl.text.trim().isEmpty) {
      _showError('Vui lòng nhập tên cây');
      return;
    }

    setState(() => _loading = true);
    try {
      final price = double.tryParse(_priceCtrl.text.replaceAll('.', '')) ?? 0;
      final ship = double.tryParse(_shipCtrl.text.replaceAll('.', '')) ?? 40000;

      String orderId;
      String? finalVariantId;

      // BƯỚC 1: Xử lý sản phẩm
      if (_productMode == 'existing') {
        finalVariantId = _selectedProduct!['id'] as String;
      } else {
        final name = _productNameCtrl.text.trim();
        String? catId;
        final catRes = await _db
            .from('categories')
            .select('id')
            .eq('name', 'Hàng Bán Lẻ')
            .limit(1);
        if ((catRes as List).isNotEmpty) {
          catId = catRes[0]['id'] as String;
        } else {
          final c = await _db
              .from('categories')
              .insert({'name': 'Hàng Bán Lẻ', 'type': 'other'})
              .select('id')
              .single();
          catId = c['id'] as String;
        }
        final prod = await _db
            .from('products')
            .insert(
                {'product_name': name, 'category_id': catId, 'is_active': true})
            .select('id')
            .single();
        final variant = await _db
            .from('product_variants')
            .insert({
              'product_id': prod['id'],
              'variant_name': name,
              'sku': _generateSku(name),
              'base_price': price,
              'cost_price': 0,
              'stock_quantity': 1,
              'is_active': true,
            })
            .select('id')
            .single();
        finalVariantId = variant['id'] as String;
      }

      // BƯỚC 2: Tạo hoặc gộp đơn
      if (merge && _existingOrder != null) {
        orderId = _existingOrder!['id'] as String;
        await _db.from('orders').update({
          'updated_at': DateTime.now().toIso8601String(),
          // Cập nhật đè luôn tên/địa chỉ mới nếu NV có gõ lại
          if (_noteCtrl.text.isNotEmpty) 'notes': _noteCtrl.text,
          if (_nameCtrl.text.isNotEmpty) 'customer_name': _nameCtrl.text,
        }).eq('id', orderId);
      } else {
        String? customerId;
        final existCust = await _db
            .from('customers')
            .select('id, full_name')
            .eq('phone', phone)
            .limit(1);
        if ((existCust as List).isNotEmpty) {
          customerId = existCust[0]['id'] as String;
          if (_nameCtrl.text.isEmpty) {
            _nameCtrl.text = existCust[0]['full_name'] ?? '';
          }
        } else {
          final c = await _db
              .from('customers')
              .insert({
                'full_name': _nameCtrl.text.trim().isEmpty
                    ? 'Khách lẻ'
                    : _nameCtrl.text.trim(),
                'phone': phone,
              })
              .select('id')
              .single();
          customerId = c['id'] as String;
        }
        final orderRes = await _db
            .from('orders')
            .insert({
              'customer_id': customerId,
              'customer_name': _nameCtrl.text.trim().isEmpty
                  ? 'Khách lẻ'
                  : _nameCtrl.text.trim(),
              'phone': phone,
              'status': 'DRAFT',
              'platform': _selectedPlatform,
              'source': 'MANUAL',
              'shipping_fee': ship,
              'notes': _noteCtrl.text.isNotEmpty ? _noteCtrl.text : null,
            })
            .select('id')
            .single();
        orderId = orderRes['id'] as String;
      }

      // BƯỚC 3: Thêm chi tiết
      await _db.from('order_details').insert({
        'order_id': orderId,
        'variant_id': finalVariantId,
        'quantity': 1,
        'unit_price': price,
        'total_price':
            price, // Lưu ý: Nếu DB của Khoa có Generated Column thì xoá dòng này nhé
      });

      if (mounted) {
        Navigator.pop(context, true);
        _showSuccess(merge ? 'Đã gộp vào đơn nháp ✓' : 'Tạo đơn thành công ✓');
      }
    } catch (e) {
      _showError('Lỗi: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(children: [
          // Handle bar
          Center(
              child: Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          )),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _kGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                    child: Text('🌿', style: TextStyle(fontSize: 18))),
              ),
              const SizedBox(width: 12),
              const Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tạo đơn thủ công',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4)),
                  Text('Đơn ngoài live – tại vườn / Zalo',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              )),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade200, shape: BoxShape.circle),
                  child: const Icon(CupertinoIcons.xmark,
                      size: 14, color: Colors.black54),
                ),
              ),
            ]),
          ),

          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                // ── Nguồn khách ──────────────────────────
                const _Label(label: 'Nguồn khách hàng'),
                _Card(
                    child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                      children: _platforms.map((p) {
                    final active = _selectedPlatform == p.$1;
                    return Expanded(
                        child: Padding(
                      padding:
                          EdgeInsets.only(right: p == _platforms.last ? 0 : 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedPlatform = p.$1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: active ? _kBlue : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: active
                                ? [
                                    BoxShadow(
                                        color: _kBlue.withOpacity(0.3),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2))
                                  ]
                                : [],
                          ),
                          child: Column(children: [
                            Text(p.$2, style: const TextStyle(fontSize: 18)),
                            const SizedBox(height: 3),
                            Text(p.$3,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: active
                                        ? Colors.white
                                        : Colors.grey.shade600)),
                          ]),
                        ),
                      ),
                    ));
                  }).toList()),
                )),
                const SizedBox(height: 14),

                // ── Thông tin khách ──────────────────────
                Row(
                  children: [
                    const _Label(label: 'Thông tin khách hàng'),
                    const Spacer(),
                    // ✅ UI: Hiện Badge Khách quen
                    if (_isLoyalCustomer)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9F0A).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          children: [
                            Icon(CupertinoIcons.star_fill,
                                size: 12, color: Color(0xFFFF9F0A)),
                            SizedBox(width: 4),
                            Text('Khách quen',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFD07A00))),
                          ],
                        ),
                      )
                  ],
                ),
                _Card(
                    child: Column(children: [
                  _Field(
                      controller: _phoneCtrl,
                      label: 'Số điện thoại *',
                      icon: CupertinoIcons.phone_fill,
                      keyboardType: TextInputType.phone,
                      onChanged: (v) {
                        // ✅ NÂNG CẤP: Gọi logic tra cứu mới
                        if (v.length >= 10) {
                          _lookupCustomerData(v);
                        } else {
                          // Ẩn badge nếu xoá bớt số
                          if (_isLoyalCustomer || _existingOrder != null) {
                            setState(() {
                              _isLoyalCustomer = false;
                              _existingOrder = null;
                            });
                          }
                        }
                      }),
                  Divider(height: 1, indent: 16, color: Colors.grey.shade100),
                  _Field(
                      controller: _nameCtrl,
                      label: 'Tên khách (tuỳ chọn)',
                      icon: CupertinoIcons.person_fill),
                ])),
                const SizedBox(height: 6),

                // Banner đơn cũ
                if (_findingExist)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12)),
                    child: const Row(children: [
                      CupertinoActivityIndicator(),
                      SizedBox(width: 10),
                      Text('Đang kiểm tra đơn cũ...'),
                    ]),
                  )
                else if (_existingOrder != null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _kGreen.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kGreen.withOpacity(0.25)),
                    ),
                    child: const Row(children: [
                      Text('🌱', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 10),
                      Expanded(
                          child: Text(
                        'Khách này đang có đơn nháp — có thể gộp thêm cây.',
                        style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF1D6E32),
                            fontWeight: FontWeight.w600),
                      )),
                    ]),
                  ),
                const SizedBox(height: 14),

                // ── Sản phẩm ─────────────────────────────
                Row(children: [
                  const _Label(label: 'Sản phẩm'),
                  const Spacer(),
                  _ToggleSwitch(
                    options: const ['Chọn từ kho', 'Nhập tay'],
                    selected: _productMode == 'existing' ? 0 : 1,
                    onChanged: (i) => setState(
                        () => _productMode = i == 0 ? 'existing' : 'manual'),
                  ),
                ]),
                const SizedBox(height: 6),

                if (_productMode == 'existing') ...[
                  _selectedProduct == null
                      ? _Card(
                          child: ListTile(
                          onTap: () => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(20))),
                            builder: (_) => SizedBox(
                              height: MediaQuery.of(context).size.height * 0.7,
                              child: _ProductPickerModal(
                                  products: _products,
                                  onSelect: (p) => setState(() {
                                        _selectedProduct = p;
                                        _priceCtrl.text =
                                            (p['base_price'] as num?)
                                                    ?.toString() ??
                                                '';
                                      })),
                            ),
                          ),
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _kBlue.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(CupertinoIcons.search_circle_fill,
                                size: 24, color: _kBlue),
                          ),
                          title: const Text('Chọn cây từ kho',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: _kBlue)),
                          subtitle: Text('${_products.length} cây có sẵn',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade500)),
                          trailing: const Icon(CupertinoIcons.chevron_right,
                              size: 14, color: Colors.grey),
                        ))
                      : _Card(
                          child: Column(children: [
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                    child: Text('🌱',
                                        style: TextStyle(fontSize: 22))),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      _selectedProduct!['variant_name']
                                              as String? ??
                                          '',
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700)),
                                  Text(
                                      'Tồn: ${_selectedProduct!['stock_quantity']} cây',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500)),
                                ],
                              )),
                              GestureDetector(
                                onTap: () => setState(() {
                                  _selectedProduct = null;
                                  _priceCtrl.clear();
                                }),
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      shape: BoxShape.circle),
                                  child: Icon(CupertinoIcons.xmark,
                                      size: 12, color: Colors.grey.shade500),
                                ),
                              ),
                            ]),
                          ),
                          Divider(
                              height: 1,
                              indent: 16,
                              color: Colors.grey.shade100),
                          _Field(
                              controller: _priceCtrl,
                              label: 'Giá chốt (đ)',
                              icon: CupertinoIcons.money_dollar,
                              keyboardType: TextInputType.number),
                        ])),
                ] else ...[
                  _Card(
                      child: Column(children: [
                    _Field(
                        controller: _productNameCtrl,
                        label: 'Tên cây / sản phẩm',
                        icon: CupertinoIcons.leaf_arrow_circlepath),
                    Divider(height: 1, indent: 16, color: Colors.grey.shade100),
                    _Field(
                        controller: _priceCtrl,
                        label: 'Giá chốt (đ)',
                        icon: CupertinoIcons.money_dollar,
                        keyboardType: TextInputType.number),
                  ])),
                ],
                const SizedBox(height: 14),

                // ── Ship & Ghi chú ───────────────────────
                if (_existingOrder == null) ...[
                  const _Label(label: 'Vận chuyển & Ghi chú'),
                  _Card(
                      child: Column(children: [
                    _Field(
                        controller: _shipCtrl,
                        label: 'Phí ship (đ)',
                        icon: CupertinoIcons.cube_box_fill,
                        keyboardType: TextInputType.number),
                    Divider(height: 1, indent: 16, color: Colors.grey.shade100),
                    _Field(
                        controller: _noteCtrl,
                        label: 'Địa chỉ / Ghi chú giao hàng',
                        icon: CupertinoIcons.location,
                        maxLines: 2),
                  ])),
                  const SizedBox(height: 20),
                ],

                // ── Buttons ──────────────────────────────
                if (_existingOrder != null) ...[
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF34C759), Color(0xFF007AFF)]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color: _kGreen.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ],
                    ),
                    child: FilledButton.icon(
                      onPressed: _loading ? null : () => _submit(merge: true),
                      icon: const Icon(CupertinoIcons.arrow_merge, size: 16),
                      label: Text(
                          _loading ? 'Đang xử lý...' : 'Gộp vào đơn nháp 🌿',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14))),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _loading ? null : () => _submit(merge: false),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        side: const BorderSide(color: _kBlue, width: 1.5),
                        foregroundColor: _kBlue),
                    child: const Text('Tạo đơn riêng',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ] else
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF007AFF), Color(0xFF5E5CE6)]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color: _kBlue.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ],
                    ),
                    child: FilledButton.icon(
                      onPressed: _loading ? null : () => _submit(merge: false),
                      icon: const Icon(CupertinoIcons.checkmark_seal_fill,
                          size: 18),
                      label: Text(_loading ? 'Đang lưu...' : 'Lưu đơn hàng 🌸',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14))),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Components ────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String label;
  const _Label({required this.label});
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
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: child,
      );
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboardType;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const _Field(
      {required this.controller,
      required this.label,
      required this.icon,
      this.keyboardType = TextInputType.text,
      this.maxLines = 1,
      this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(children: [
          Icon(icon, size: 18, color: Colors.grey.shade400),
          const SizedBox(width: 12),
          Expanded(
              child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: label,
              hintStyle: TextStyle(
                  color: Colors.grey.shade400, fontWeight: FontWeight.w400),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          )),
        ]),
      );
}

class _ToggleSwitch extends StatelessWidget {
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;
  const _ToggleSwitch(
      {required this.options, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
              options.length,
              (i) => GestureDetector(
                    onTap: () => onChanged(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color:
                            selected == i ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                        boxShadow: selected == i
                            ? [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1))
                              ]
                            : [],
                      ),
                      child: Text(options[i],
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected == i
                                  ? Colors.black
                                  : Colors.grey.shade500)),
                    ),
                  )),
        ),
      );
}

class _ProductPickerModal extends StatefulWidget {
  final List<Map<String, dynamic>> products;
  final ValueChanged<Map<String, dynamic>> onSelect;
  const _ProductPickerModal({required this.products, required this.onSelect});
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
              onTap: () {
                Navigator.pop(context);
                widget.onSelect(p);
              },
            );
          },
        )),
      ]);
}

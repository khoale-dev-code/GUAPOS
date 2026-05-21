// create_order_sheet.dart
// Flow: Tap bình luận → Sheet chốt đơn → Chọn cây → Tạo đơn → In phiếu
//
// LOGIC ĐẶC THÙ:
//   Mỗi chậu hoa (dù cùng loại) là cá thể riêng — VD: Lan Hồ Điệp
//   có thể 30 chậu cùng tên nhưng hình thù, màu sắc khác nhau.
//   → Sau khi chốt đơn BẮT BUỘC in phiếu dán lên chậu để định danh.
//
// PHÂN TÁCH FILE:
//   - live_order_ui.dart       → palette, shared widgets
//   - plant_picker_sheet.dart  → bottom-sheet chọn cây từ kho
//   - plant_label_screen.dart  → màn hình xem + in phiếu
//   - order_result_model.dart  → model kết quả đơn

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gua_pos/features/livestream/data/order_result_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../shared/models/livestream_models.dart';
import 'live_order_ui.dart';
import 'plant_label_screen.dart';
import 'plant_picker_sheet.dart';

class CreateOrderSheet extends StatefulWidget {
  final LiveComment comment;
  final LiveSession session;

  const CreateOrderSheet({
    super.key,
    required this.comment,
    required this.session,
  });

  @override
  State<CreateOrderSheet> createState() => _CreateOrderSheetState();
}

class _CreateOrderSheetState extends State<CreateOrderSheet> {
  final _db = Supabase.instance.client;

  // ── Controllers ───────────────────────────────────────────
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _noteCtrl = TextEditingController(); // đặc điểm cây → in phiếu
  final _manualNameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _shipCtrl = TextEditingController(text: '40000');

  // ── State ─────────────────────────────────────────────────
  bool _loading = false;
  bool _checkingOrder = false;
  String _mode = 'existing'; // 'existing' | 'manual'

  Map<String, dynamic>? _existingDraft;
  Map<String, dynamic>? _selectedPlant;
  List<Map<String, dynamic>> _plants = [];

  /// Sau khi tạo đơn thành công → chuyển sang màn hình in phiếu
  OrderResult? _result;

  @override
  void initState() {
    super.initState();
    _prefillFromComment();
    _loadPlants();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    _manualNameCtrl.dispose();
    _priceCtrl.dispose();
    _shipCtrl.dispose();
    super.dispose();
  }

  // ── Tự điền SĐT + gợi ý đặc điểm cây từ nội dung comment ─
  void _prefillFromComment() {
    _nameCtrl.text = widget.comment.commenterName;

    final phone = RegExp(r'(0[35789]\d{8})')
        .firstMatch(widget.comment.commentText)
        ?.group(0);
    if (phone != null) {
      _phoneCtrl.text = phone;
      _checkExistingDraft(phone);
    }

    // Phần text sau SĐT thường là mô tả cây khách muốn
    final hint = widget.comment.commentText
        .replaceAll(RegExp(r'0[35789]\d{8}'), '')
        .trim();
    if (hint.isNotEmpty) _noteCtrl.text = hint;
  }

  // ── Kiểm tra đơn DRAFT cũ của khách trong phiên ───────────
  Future<void> _checkExistingDraft(String phone) async {
    setState(() => _checkingOrder = true);
    try {
      final res = await _db
          .from('orders')
          .select('id, order_code, status, final_amount')
          .eq('session_id', widget.session.id)
          .eq('phone', phone)
          .eq('status', 'DRAFT')
          .limit(1);
      setState(() => _existingDraft = (res as List).isNotEmpty ? res[0] : null);
    } catch (_) {
    } finally {
      setState(() => _checkingOrder = false);
    }
  }

  // ── Load danh sách cây còn hàng ───────────────────────────
  Future<void> _loadPlants() async {
    try {
      final res = await _db
          .from('product_variants')
          .select(
              'id, variant_name, base_price, stock_quantity, sku, thumbnail_url, products(product_name)')
          .eq('is_active', true)
          .gt('stock_quantity', 0)
          .order('variant_name');
      setState(() => _plants = List<Map<String, dynamic>>.from(res));
    } catch (_) {}
  }

  // ── Mở picker chọn cây ────────────────────────────────────
  void _openPlantPicker() {
    PlantPickerSheet.show(
      context,
      products: _plants,
      onSelect: (plant) => setState(() {
        _selectedPlant = plant;
        _priceCtrl.text = (plant['base_price'] as num?)?.toString() ?? '';
      }),
    );
  }

  // ── SKU tự sinh cho sản phẩm nhập tay ────────────────────
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

  // ============================================================
  // CHỐT ĐƠN
  // merge = true  → thêm cây vào đơn DRAFT cũ
  // merge = false → tạo đơn mới
  // ============================================================
  Future<void> _submit({required bool merge}) async {
    final phone = _phoneCtrl.text.trim();

    // Validate
    if (phone.isEmpty) {
      _err('Vui lòng nhập số điện thoại');
      return;
    }
    if (_mode == 'existing' && _selectedPlant == null) {
      _err('Vui lòng chọn cây từ kho');
      return;
    }
    if (_mode == 'manual' && _manualNameCtrl.text.trim().isEmpty) {
      _err('Vui lòng nhập tên cây');
      return;
    }

    setState(() => _loading = true);
    try {
      final price = double.tryParse(_priceCtrl.text.replaceAll('.', '')) ?? 0;
      final ship = double.tryParse(_shipCtrl.text.replaceAll('.', '')) ?? 40000;

      // ── 1. Xử lý sản phẩm ──────────────────────────────
      String? variantId;
      String productName = '';
      String sku = '';

      if (_mode == 'existing') {
        variantId = _selectedPlant!['id'] as String;
        productName = _selectedPlant!['variant_name'] as String? ?? '';
        sku = _selectedPlant!['sku'] as String? ?? '';
      } else {
        productName = _manualNameCtrl.text.trim();
        sku = _generateSku(productName);
        variantId = await _createManualVariant(productName, sku, price);
        if (variantId == null) return; // lỗi đã được báo
      }

      // ── 2. Tạo / gộp đơn ────────────────────────────────
      final (orderId, orderCode) = merge && _existingDraft != null
          ? await _mergeIntoExistingOrder()
          : await _createNewOrder(phone, ship);

      // ── 3. Thêm chi tiết đơn ────────────────────────────
      final detailRes = await _db
          .from('order_details')
          .insert({
            'order_id': orderId,
            'variant_id': variantId,
            'quantity': 1,
            'unit_price': price,
            'total_price': price,
          })
          .select('id')
          .single();
      final detailId = detailRes['id'] as String;

      if (!mounted) return;

      // ── 4. Chuyển sang màn hình phiếu dán ────────────────
      setState(() {
        _result = OrderResult(
          orderId: orderId,
          orderCode: orderCode,
          detailId: detailId,
          customerName:
              _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : phone,
          phone: phone,
          productName: productName,
          sku: sku,
          price: price,
          ship: ship,
          note: _noteCtrl.text.trim(),
          platform: widget.session.platform,
          isMerged: merge,
          createdAt: DateTime.now(),
        );
        _loading = false;
      });
    } catch (e) {
      _err('Lỗi: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Tạo variant mới cho cây nhập tay ──────────────────────
  Future<String?> _createManualVariant(
      String name, String sku, double price) async {
    try {
      // Tìm hoặc tạo category mặc định
      String catId;
      final catRes = await _db
          .from('categories')
          .select('id')
          .eq('name', 'Hàng Livestream')
          .limit(1);
      if ((catRes as List).isNotEmpty) {
        catId = catRes[0]['id'] as String;
      } else {
        final c = await _db
            .from('categories')
            .insert({'name': 'Hàng Livestream', 'type': 'other'})
            .select('id')
            .single();
        catId = c['id'] as String;
      }

      final prod = await _db
          .from('products')
          .insert({
            'product_name': name,
            'category_id': catId,
            'is_active': true,
          })
          .select('id')
          .single();

      final variant = await _db
          .from('product_variants')
          .insert({
            'product_id': prod['id'],
            'variant_name': name,
            'sku': sku,
            'base_price': price,
            'cost_price': 0,
            'stock_quantity': 1,
            'is_active': true,
          })
          .select('id')
          .single();

      return variant['id'] as String;
    } catch (e) {
      _err('Lỗi tạo sản phẩm: $e');
      if (mounted) setState(() => _loading = false);
      return null;
    }
  }

  // ── Gộp cây vào đơn DRAFT cũ ──────────────────────────────
  Future<(String, String)> _mergeIntoExistingOrder() async {
    final orderId = _existingDraft!['id'] as String;
    final orderCode = _existingDraft!['order_code'] as String? ??
        '#${orderId.substring(0, 8).toUpperCase()}';
    await _db.from('orders').update({
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', orderId);
    return (orderId, orderCode);
  }

  // ── Tạo đơn mới ───────────────────────────────────────────
  Future<(String, String)> _createNewOrder(String phone, double ship) async {
    // Upsert khách hàng
    String customerId;
    final existing =
        await _db.from('customers').select('id').eq('phone', phone).limit(1);
    if ((existing as List).isNotEmpty) {
      customerId = existing[0]['id'] as String;
    } else {
      final c = await _db
          .from('customers')
          .insert({
            'full_name': _nameCtrl.text.trim().isNotEmpty
                ? _nameCtrl.text.trim()
                : phone,
            'phone': phone,
          })
          .select('id')
          .single();
      customerId = c['id'] as String;
    }

    final source =
        widget.session.platform == 'tiktok' ? 'LIVESTREAM_TT' : 'LIVESTREAM_FB';

    final res = await _db
        .from('orders')
        .insert({
          'customer_id': customerId,
          'customer_name':
              _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : phone,
          'phone': phone,
          'session_id': widget.session.id,
          'platform': widget.session.platform,
          'source': source,
          'status': 'DRAFT',
          'shipping_fee': ship,
          'notes': _noteCtrl.text.isNotEmpty ? _noteCtrl.text : null,
        })
        .select('id, order_code')
        .single();

    final orderId = res['id'] as String;
    final orderCode = res['order_code'] as String? ??
        '#${orderId.substring(0, 8).toUpperCase()}';
    return (orderId, orderCode);
  }

  void _err(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: kRed,
        behavior: SnackBarBehavior.floating));
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    // Đã chốt đơn → hiện phiếu dán
    if (_result != null) {
      return PlantLabelScreen(
        result: _result!,
        onDone: () => Navigator.pop(context),
        onAddAnotherPlant: () => setState(() => _result = null),
      );
    }
    return _buildForm();
  }

  Widget _buildForm() {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(children: [
          const SheetHandle(),
          _FormHeader(onClose: () => Navigator.pop(context)),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                // Comment gốc từ live
                _CommentBubble(comment: widget.comment),
                const SizedBox(height: 12),

                // Banner đơn cũ
                _DraftBanner(checking: _checkingOrder, draft: _existingDraft),
                const SizedBox(height: 4),

                // ── Khách hàng ──────────────────────
                const SectionLabel(label: 'Khách hàng'),
                WhiteCard(
                  child: Column(children: [
                    FieldRow(
                      controller: _phoneCtrl,
                      label: 'Số điện thoại *',
                      icon: CupertinoIcons.phone_fill,
                      keyboardType: TextInputType.phone,
                      onChanged: (v) {
                        if (v.length == 10) _checkExistingDraft(v);
                      },
                    ),
                    const HDivider(),
                    FieldRow(
                        controller: _nameCtrl,
                        label: 'Tên khách (từ live)',
                        icon: CupertinoIcons.person_fill),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── Cây chốt ────────────────────────
                Row(children: [
                  const SectionLabel(label: 'Cây chốt cho khách'),
                  const Spacer(),
                  _ModeToggle(
                      mode: _mode, onChanged: (v) => setState(() => _mode = v)),
                ]),
                const SizedBox(height: 8),

                if (_mode == 'existing')
                  _PlantSection(
                    selectedPlant: _selectedPlant,
                    priceCtrl: _priceCtrl,
                    noteCtrl: _noteCtrl,
                    onPickPlant: _openPlantPicker,
                    onClearPlant: () => setState(() {
                      _selectedPlant = null;
                      _priceCtrl.clear();
                    }),
                  )
                else
                  _ManualSection(
                    nameCtrl: _manualNameCtrl,
                    priceCtrl: _priceCtrl,
                    noteCtrl: _noteCtrl,
                  ),

                const SizedBox(height: 16),

                // ── Ship (chỉ hiện khi tạo đơn mới) ─
                if (_existingDraft == null) ...[
                  const SectionLabel(label: 'Phí vận chuyển'),
                  WhiteCard(
                    child: FieldRow(
                      controller: _shipCtrl,
                      label: 'Phí ship (đ) — mặc định 40.000đ',
                      icon: CupertinoIcons.cube_box_fill,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Nút chốt ─────────────────────────
                _ActionButtons(
                  loading: _loading,
                  hasExistingDraft: _existingDraft != null,
                  onMerge: () => _submit(merge: true),
                  onNew: () => _submit(merge: false),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ============================================================
// SUB-WIDGETS NỘI BỘ
// ============================================================

// ── Header sheet ─────────────────────────────────────────────
class _FormHeader extends StatelessWidget {
  final VoidCallback onClose;
  const _FormHeader({required this.onClose});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: kGreen.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
            child:
                const Center(child: Text('🌸', style: TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Chốt cây',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4)),
                Text('Chọn cây → Tạo đơn → In phiếu dán',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          SheetCloseButton(onTap: onClose),
        ]),
      );
}

// ── Comment bubble gốc ───────────────────────────────────────
class _CommentBubble extends StatelessWidget {
  final LiveComment comment;
  const _CommentBubble({required this.comment});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xFFE9F0FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBBCEF8))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(CupertinoIcons.chat_bubble_fill, size: 16, color: kBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(comment.commenterName,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: kBlue)),
                  const SizedBox(height: 2),
                  Text(comment.commentText,
                      style: const TextStyle(fontSize: 14, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      );
}

// ── Banner đơn DRAFT cũ ───────────────────────────────────────
class _DraftBanner extends StatelessWidget {
  final bool checking;
  final Map<String, dynamic>? draft;
  const _DraftBanner({required this.checking, required this.draft});

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return InfoBox(
          color: kBlue,
          icon: CupertinoIcons.hourglass,
          text: 'Đang kiểm tra đơn cũ của khách...');
    }
    if (draft != null) {
      return InfoBox(
          color: kGreen,
          icon: CupertinoIcons.cart_fill,
          text:
              'Khách đã có đơn DRAFT trong phiên — bấm "Gộp đơn" để thêm cây này vào');
    }
    return const SizedBox.shrink();
  }
}

// ── Toggle chọn mode cây ─────────────────────────────────────
class _ModeToggle extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onChanged;
  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _Tab(
              label: 'Từ kho', value: 'existing', mode: mode, onTap: onChanged),
          _Tab(
              label: 'Nhập tay', value: 'manual', mode: mode, onTap: onChanged),
        ]),
      );
}

class _Tab extends StatelessWidget {
  final String label, value, mode;
  final ValueChanged<String> onTap;
  const _Tab(
      {required this.label,
      required this.value,
      required this.mode,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = mode == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: active
                ? [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 4,
                        offset: const Offset(0, 1))
                  ]
                : []),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? const Color(0xFF1C1C1E) : Colors.grey)),
      ),
    );
  }
}

// ── Section cây từ kho ───────────────────────────────────────
class _PlantSection extends StatelessWidget {
  final Map<String, dynamic>? selectedPlant;
  final TextEditingController priceCtrl, noteCtrl;
  final VoidCallback onPickPlant, onClearPlant;

  const _PlantSection({
    required this.selectedPlant,
    required this.priceCtrl,
    required this.noteCtrl,
    required this.onPickPlant,
    required this.onClearPlant,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedPlant == null) {
      // Nút chọn cây
      return GestureDetector(
        onTap: onPickPlant,
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: kBlue.withOpacity(0.4),
                width: 1.5,
                strokeAlign: BorderSide.strokeAlignInside),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: kBlue.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(CupertinoIcons.leaf_arrow_circlepath,
                    size: 18, color: kBlue),
              ),
              const SizedBox(width: 10),
              const Text('Chọn cây từ kho',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: kBlue)),
              const SizedBox(width: 6),
              const Icon(CupertinoIcons.chevron_right, size: 14, color: kBlue),
            ],
          ),
        ),
      );
    }

    // Card cây đã chọn
    final stock = selectedPlant!['stock_quantity'] as int? ?? 0;
    return WhiteCard(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12)),
              child: const Center(
                  child: Text('🌱', style: TextStyle(fontSize: 24))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(selectedPlant!['variant_name'] as String? ?? '',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: stock > 3
                            ? kGreen.withOpacity(0.1)
                            : kRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('Tồn: $stock cây',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: stock > 3 ? kGreen : kRed)),
                    ),
                  ]),
            ),
            // Đổi cây
            GestureDetector(
              onTap: onClearPlant,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                    color: Colors.grey.shade100, shape: BoxShape.circle),
                child: Icon(CupertinoIcons.xmark,
                    size: 12, color: Colors.grey.shade500),
              ),
            ),
          ]),
        ),
        const HDivider(),
        FieldRow(
          controller: priceCtrl,
          label: 'Giá bán cây này (đ)',
          icon: CupertinoIcons.money_dollar,
          keyboardType: TextInputType.number,
        ),
        const HDivider(),
        // QUAN TRỌNG: Đặc điểm cây được in lên phiếu để tránh nhầm
        FieldRow(
          controller: noteCtrl,
          label: 'Đặc điểm cây (VD: 3 cành, màu tím đậm) — IN LÊN PHIẾU',
          icon: CupertinoIcons.tag,
          maxLines: 2,
        ),
      ]),
    );
  }
}

// ── Section cây nhập tay ─────────────────────────────────────
class _ManualSection extends StatelessWidget {
  final TextEditingController nameCtrl, priceCtrl, noteCtrl;
  const _ManualSection(
      {required this.nameCtrl,
      required this.priceCtrl,
      required this.noteCtrl});

  @override
  Widget build(BuildContext context) => WhiteCard(
        child: Column(children: [
          FieldRow(
            controller: nameCtrl,
            label: 'Tên cây / sản phẩm *',
            icon: CupertinoIcons.leaf_arrow_circlepath,
          ),
          const HDivider(),
          FieldRow(
            controller: priceCtrl,
            label: 'Giá bán (đ)',
            icon: CupertinoIcons.money_dollar,
            keyboardType: TextInputType.number,
          ),
          const HDivider(),
          FieldRow(
            controller: noteCtrl,
            label: 'Đặc điểm cây — in lên phiếu',
            icon: CupertinoIcons.tag,
            maxLines: 2,
          ),
        ]),
      );
}

// ── Nút hành động ─────────────────────────────────────────────
class _ActionButtons extends StatelessWidget {
  final bool loading, hasExistingDraft;
  final VoidCallback onMerge, onNew;

  const _ActionButtons({
    required this.loading,
    required this.hasExistingDraft,
    required this.onMerge,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    if (hasExistingDraft) {
      return Column(children: [
        GradientButton(
          label: loading ? 'Đang xử lý...' : '🌿  Gộp cây vào đơn & In phiếu',
          colors: const [kGreen, kBlue],
          icon: CupertinoIcons.arrow_merge,
          onTap: loading ? null : onMerge,
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: loading ? null : onNew,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            side: const BorderSide(color: kBlue, width: 1.5),
            foregroundColor: kBlue,
          ),
          child: const Text('Tạo đơn riêng & In phiếu',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]);
    }

    return GradientButton(
      label: loading ? 'Đang tạo đơn...' : '🖨️  Chốt đơn & In phiếu dán cây',
      colors: const [kBlue, Color(0xFF5E5CE6)],
      icon: CupertinoIcons.printer_fill,
      onTap: loading ? null : onNew,
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class ProductFormScreen extends StatefulWidget {
  final Map<String, dynamic>? variant;
  const ProductFormScreen({super.key, this.variant});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _db = Supabase.instance.client;

  final _nameCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _addStockCtrl = TextEditingController();

  List<Map<String, dynamic>> _categories = [];
  String? _selectedCategoryId;
  String? _existingImageUrl;
  File? _pickedImage;
  bool _loading = false;
  bool _isEdit = false;

  @override
  void initState() {
    super.initState();
    _isEdit = widget.variant != null;
    _loadCategories();
    if (_isEdit) _fillForm();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _priceCtrl.dispose();
    _costCtrl.dispose();
    _stockCtrl.dispose();
    _addStockCtrl.dispose();
    super.dispose();
  }

  void _fillForm() {
    final v = widget.variant!;
    _nameCtrl.text = v['variant_name'] as String? ?? '';
    _skuCtrl.text = v['sku'] as String? ?? '';
    _priceCtrl.text = (v['base_price'] as num?)?.toStringAsFixed(0) ?? '';
    _costCtrl.text = (v['cost_price'] as num?)?.toStringAsFixed(0) ?? '';
    _stockCtrl.text = (v['stock_quantity'] as int?)?.toString() ?? '0';
    _existingImageUrl =
        v['thumbnail_url'] as String? ?? v['image_url'] as String?;
    _selectedCategoryId = (v['products'] as Map?)?['category_id'] as String?;
  }

  Future<void> _loadCategories() async {
    try {
      final res = await _db.from('categories').select('id, name').order('name');
      setState(() => _categories = List<Map<String, dynamic>>.from(res));
    } catch (_) {}
  }

  // ── Tự sinh SKU nếu để trống ────────────────────────────
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

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 800, imageQuality: 80);
    if (picked == null) return;
    setState(() => _pickedImage = File(picked.path));
  }

  Future<String?> _uploadImage(String variantId) async {
    if (_pickedImage == null) return _existingImageUrl;
    try {
      final bytes = await _pickedImage!.readAsBytes();
      final ext = _pickedImage!.path.split('.').last;
      final path = 'products/$variantId.$ext';
      await _db.storage.from('product-images').uploadBinary(path, bytes,
          fileOptions: const FileOptions(upsert: true));
      return _db.storage.from('product-images').getPublicUrl(path);
    } catch (e) {
      _showError('Lỗi upload ảnh: $e');
      return _existingImageUrl;
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _showError('Vui lòng nhập tên cây');
      return;
    }
    final price = double.tryParse(_priceCtrl.text.replaceAll('.', '')) ?? 0;
    if (price <= 0) {
      _showError('Vui lòng nhập giá bán');
      return;
    }

    setState(() => _loading = true);
    try {
      final cost = double.tryParse(_costCtrl.text.replaceAll('.', '')) ?? 0;
      final stock = int.tryParse(_stockCtrl.text) ?? 0;

      // SKU: dùng giá trị người dùng nhập, nếu trống thì tự sinh
      final sku = _skuCtrl.text.trim().isEmpty
          ? _generateSku(_nameCtrl.text)
          : _skuCtrl.text.trim();

      if (_isEdit) {
        final variantId = widget.variant!['id'] as String;
        final imgUrl = await _uploadImage(variantId);

        final productId =
            (widget.variant!['products'] as Map?)?['id'] as String?;
        if (productId != null) {
          await _db.from('products').update({
            'product_name': _nameCtrl.text.trim(),
            'category_id': _selectedCategoryId,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', productId);
        }

        await _db.from('product_variants').update({
          'variant_name': _nameCtrl.text.trim(),
          'sku': sku, // ✅ không bao giờ null
          'base_price': price,
          'cost_price': cost,
          'stock_quantity': stock,
          'thumbnail_url': imgUrl,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', variantId);

        final addStock = int.tryParse(_addStockCtrl.text) ?? 0;
        if (addStock > 0) {
          await _db.from('product_variants').update({
            'stock_quantity': stock + addStock,
          }).eq('id', variantId);

          await _db.from('inventory_transactions').insert({
            'variant_id': variantId,
            'transaction_type': 'IMPORT', // ✅ chữ hoa đúng constraint
            'quantity_changed': addStock,
            'reference_type': 'manual',
            'note': 'Nhập thêm kho thủ công',
          });
        }
      } else {
        // Tạo product
        final productRes = await _db
            .from('products')
            .insert({
              'product_name': _nameCtrl.text.trim(),
              'category_id': _selectedCategoryId,
              'is_active': true,
            })
            .select('id')
            .single();
        final productId = productRes['id'] as String;

        // Tạo variant — SKU luôn có giá trị
        final variantRes = await _db
            .from('product_variants')
            .insert({
              'product_id': productId,
              'variant_name': _nameCtrl.text.trim(),
              'sku': sku, // ✅ auto-gen nếu trống
              'base_price': price,
              'cost_price': cost,
              'stock_quantity': stock,
              'is_active': true,
            })
            .select('id')
            .single();
        final variantId = variantRes['id'] as String;

        // Upload ảnh
        final imgUrl = await _uploadImage(variantId);
        if (imgUrl != null) {
          await _db
              .from('product_variants')
              .update({'thumbnail_url': imgUrl}).eq('id', variantId);
        }

        // Ghi log nhập kho lần đầu
        if (stock > 0) {
          await _db.from('inventory_transactions').insert({
            'variant_id': variantId,
            'transaction_type': 'IMPORT', // ✅ chữ hoa đúng constraint
            'quantity_changed': stock,
            'reference_type': 'initial',
            'note': 'Nhập kho lần đầu',
          });
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isEdit ? 'Đã cập nhật ✓' : 'Đã thêm cây mới ✓'),
          backgroundColor: const Color(0xFF34C759),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      _showError('Lỗi lưu: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Xoá cây này?'),
        content: const Text('Cây sẽ bị ẩn khỏi danh sách.'),
        actions: [
          CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Xoá')),
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Huỷ')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _loading = true);
    try {
      await _db.from('product_variants').update({
        'is_active': false,
        'deleted_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.variant!['id']);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError('Lỗi xoá: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showError(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFFFF3B30),
          behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(CupertinoIcons.chevron_left, size: 20),
        ),
        title: Text(_isEdit ? 'Sửa thông tin cây' : 'Thêm cây mới',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          if (_isEdit)
            IconButton(
              onPressed: _loading ? null : _delete,
              icon: const Icon(CupertinoIcons.trash,
                  size: 20, color: Color(0xFFFF3B30)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ảnh
            _SectionLabel(label: 'Ảnh cây'),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: _buildImagePreview(),
              ),
            ),
            const SizedBox(height: 12),

            // Thông tin
            _SectionLabel(label: 'Thông tin cây'),
            _Card(
                child: Column(children: [
              _Field(
                  controller: _nameCtrl,
                  label: 'Tên cây / sản phẩm *',
                  icon: CupertinoIcons.leaf_arrow_circlepath),
              _Divider(),
              // SKU: hint rõ là tuỳ chọn, nếu để trống sẽ tự sinh
              _Field(
                  controller: _skuCtrl,
                  label: 'Mã SKU (để trống sẽ tự sinh)',
                  icon: CupertinoIcons.barcode),
              _Divider(),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Icon(CupertinoIcons.tag,
                      size: 18, color: Colors.grey.shade400),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _selectedCategoryId,
                        hint: Text('Loại cây',
                            style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 15)),
                        isExpanded: true,
                        icon: Icon(CupertinoIcons.chevron_down,
                            size: 14, color: Colors.grey.shade400),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('Không phân loại')),
                          ..._categories.map((c) => DropdownMenuItem(
                                value: c['id'] as String,
                                child: Text(c['name'] as String),
                              )),
                        ],
                        onChanged: (v) =>
                            setState(() => _selectedCategoryId = v),
                        style: const TextStyle(
                            fontSize: 15, color: Color(0xFF1C1C1E)),
                      ),
                    ),
                  ),
                ]),
              ),
            ])),
            const SizedBox(height: 12),

            // Giá
            _SectionLabel(label: 'Giá'),
            _Card(
                child: Column(children: [
              _Field(
                  controller: _priceCtrl,
                  label: 'Giá bán (đ) *',
                  icon: CupertinoIcons.money_dollar,
                  keyboardType: TextInputType.number),
              _Divider(),
              _Field(
                  controller: _costCtrl,
                  label: 'Giá nhập / vốn (đ)',
                  icon: CupertinoIcons.arrow_down_circle,
                  keyboardType: TextInputType.number),
            ])),
            const SizedBox(height: 12),

            // Tồn kho
            _SectionLabel(label: 'Tồn kho'),
            _Card(
                child: Column(children: [
              _Field(
                controller: _stockCtrl,
                label: _isEdit ? 'Tồn kho hiện tại' : 'Số lượng ban đầu',
                icon: CupertinoIcons.cube_box_fill,
                keyboardType: TextInputType.number,
                readOnly: _isEdit,
              ),
              if (_isEdit) ...[
                _Divider(),
                _Field(
                    controller: _addStockCtrl,
                    label: 'Nhập thêm (để trống nếu không nhập)',
                    icon: CupertinoIcons.add_circled,
                    keyboardType: TextInputType.number),
              ],
            ])),
            const SizedBox(height: 28),

            FilledButton.icon(
              onPressed: _loading ? null : _save,
              icon: Icon(
                  _loading
                      ? CupertinoIcons.hourglass
                      : CupertinoIcons.checkmark_alt,
                  size: 16),
              label: Text(
                  _loading
                      ? 'Đang lưu...'
                      : (_isEdit ? 'Lưu thay đổi' : 'Thêm cây'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF34C759),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    if (_pickedImage != null) {
      return Stack(fit: StackFit.expand, children: [
        ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(_pickedImage!, fit: BoxFit.cover)),
        Positioned(right: 8, top: 8, child: _ChangeImgBtn()),
      ]);
    }
    if (_existingImageUrl != null && _existingImageUrl!.isNotEmpty) {
      return Stack(fit: StackFit.expand, children: [
        ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(_existingImageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _AddImgPlaceholder())),
        Positioned(right: 8, top: 8, child: _ChangeImgBtn()),
      ]);
    }
    return _AddImgPlaceholder();
  }
}

// ── Components ───────────────────────────────────────────────
class _AddImgPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.camera, size: 32, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text('Thêm ảnh cây',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade400)),
        ],
      );
}

class _ChangeImgBtn extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: Colors.black54, borderRadius: BorderRadius.circular(10)),
        child: const Text('Đổi ảnh',
            style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      );
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
                letterSpacing: 0.5)),
      );
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: child,
      );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Divider(height: 1, color: Colors.grey.shade100),
      );
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboardType;
  final bool readOnly;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Icon(icon, size: 18, color: Colors.grey.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              readOnly: readOnly,
              style: TextStyle(
                  fontSize: 15,
                  color: readOnly
                      ? Colors.grey.shade400
                      : const Color(0xFF1C1C1E)),
              inputFormatters: keyboardType == TextInputType.number
                  ? [FilteringTextInputFormatter.digitsOnly]
                  : null,
              decoration: InputDecoration(
                hintText: label,
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ]),
      );
}

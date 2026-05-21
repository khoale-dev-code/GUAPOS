import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// CATEGORY SCREEN – Quản lý danh mục cây
// type phải đúng constraint: 'plant' | 'material' | 'accessory' | 'other'
// ============================================================

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;

  // Các giá trị type hợp lệ theo DB constraint
  static const _typeOptions = [
    ('plant', '🌱 Cây / Hoa'),
    ('accessory', '🪴 Chậu / Phụ kiện'),
    ('material', '🌿 Phân bón / Giá thể'),
    ('other', '📦 Khác'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _db
          .from('categories')
          .select('id, name, type, created_at')
          .isFilter('deleted_at', null)
          .order('name');
      setState(() => _categories = List<Map<String, dynamic>>.from(res));
    } catch (e) {
      _showError('Lỗi tải danh mục: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showAddDialog() => _showFormDialog(null);
  void _showEditDialog(Map<String, dynamic> cat) => _showFormDialog(cat);

  void _showFormDialog(Map<String, dynamic>? cat) {
    final isEdit = cat != null;
    final nameCtrl = TextEditingController(text: cat?['name'] as String? ?? '');
    // Mặc định type = 'plant' nếu thêm mới
    String selectedType = cat?['type'] as String? ?? 'plant';

    showCupertinoDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => CupertinoAlertDialog(
          title: Text(isEdit ? 'Sửa danh mục' : 'Thêm danh mục'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: nameCtrl,
                placeholder: 'Tên danh mục *  (VD: Lan Hồ Điệp)',
                autofocus: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              const SizedBox(height: 10),
              // Chọn loại bằng segmented control
              const Text('Loại:',
                  style: TextStyle(
                      fontSize: 12, color: CupertinoColors.secondaryLabel)),
              const SizedBox(height: 6),
              // Dùng column vì 4 options không vừa 1 hàng
              Column(
                children: _typeOptions.map((opt) {
                  final selected = selectedType == opt.$1;
                  return GestureDetector(
                    onTap: () => setS(() => selectedType = opt.$1),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? CupertinoColors.activeBlue
                            : CupertinoColors.systemGrey6,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Text(opt.$2,
                              style: TextStyle(
                                fontSize: 13,
                                color: selected
                                    ? CupertinoColors.white
                                    : CupertinoColors.label,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              )),
                          const Spacer(),
                          if (selected)
                            const Icon(CupertinoIcons.checkmark_alt,
                                size: 14, color: CupertinoColors.white),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Huỷ'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(context);
                isEdit
                    ? await _update(cat!['id'] as String, name, selectedType)
                    : await _create(name, selectedType);
              },
              child: Text(isEdit ? 'Lưu' : 'Thêm'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create(String name, String type) async {
    try {
      await _db.from('categories').insert({'name': name, 'type': type});
      _showSuccess('Đã thêm "$name" ✓');
      _load();
    } catch (e) {
      _showError('Lỗi thêm: $e');
    }
  }

  Future<void> _update(String id, String name, String type) async {
    try {
      await _db
          .from('categories')
          .update({'name': name, 'type': type}).eq('id', id);
      _showSuccess('Đã cập nhật ✓');
      _load();
    } catch (e) {
      _showError('Lỗi cập nhật: $e');
    }
  }

  Future<void> _delete(Map<String, dynamic> cat) async {
    final name = cat['name'] as String;

    // Kiểm tra còn sản phẩm không
    final check = await _db
        .from('products')
        .select('id')
        .eq('category_id', cat['id'])
        .isFilter('deleted_at', null)
        .limit(1);

    if ((check as List).isNotEmpty) {
      _showError('"$name" còn sản phẩm, không thể xoá');
      return;
    }

    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Xoá danh mục?'),
        content: Text('Xoá "$name"?'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    try {
      await _db.from('categories').delete().eq('id', cat['id']);
      _showSuccess('Đã xoá "$name" ✓');
      _load();
    } catch (e) {
      _showError('Lỗi xoá: $e');
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(msg),
            backgroundColor: const Color(0xFFFF3B30),
            behavior: SnackBarBehavior.floating),
      );

  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(msg),
            backgroundColor: const Color(0xFF34C759),
            behavior: SnackBarBehavior.floating),
      );

  String _typeLabel(String? type) {
    switch (type) {
      case 'plant':
        return '🌱 Cây / Hoa';
      case 'accessory':
        return '🪴 Chậu / Phụ kiện';
      case 'material':
        return '🌿 Phân bón / Giá thể';
      default:
        return '📦 Khác';
    }
  }

  Color _typeColor(String? type) {
    switch (type) {
      case 'plant':
        return const Color(0xFF34C759);
      case 'accessory':
        return const Color(0xFFFF9F0A);
      case 'material':
        return const Color(0xFF5E5CE6);
      default:
        return const Color(0xFF8E8E93);
    }
  }

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
        title: const Text('Danh mục',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _showAddDialog,
              icon: const Icon(CupertinoIcons.add, size: 16),
              label: const Text('Thêm'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                textStyle:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : _categories.isEmpty
              ? _EmptyState(onAdd: _showAddDialog)
              : RefreshIndicator.adaptive(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _categories.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 0),
                    itemBuilder: (ctx, i) {
                      final cat = _categories[i];
                      final isFirst = i == 0;
                      final isLast = i == _categories.length - 1;
                      final type = cat['type'] as String?;

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                            top: isFirst
                                ? const Radius.circular(14)
                                : Radius.zero,
                            bottom: isLast
                                ? const Radius.circular(14)
                                : Radius.zero,
                          ),
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              leading: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: _typeColor(type).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    _typeLabel(type).split(' ').first,
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                ),
                              ),
                              title: Text(cat['name'] as String,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                _typeLabel(type),
                                style: TextStyle(
                                    fontSize: 12, color: _typeColor(type)),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed: () => _showEditDialog(cat),
                                    icon: Icon(CupertinoIcons.pencil,
                                        size: 18, color: Colors.grey.shade400),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  IconButton(
                                    onPressed: () => _delete(cat),
                                    icon: const Icon(CupertinoIcons.trash,
                                        size: 18, color: Color(0xFFFF3B30)),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ),
                            if (!isLast)
                              Divider(
                                  height: 1,
                                  indent: 68,
                                  color: Colors.grey.shade100),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🗂️', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 12),
            const Text('Chưa có danh mục nào',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Tạo danh mục để phân loại cây dễ hơn',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(CupertinoIcons.add, size: 16),
              label: const Text('Thêm danh mục'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                minimumSize: const Size(180, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      );
}

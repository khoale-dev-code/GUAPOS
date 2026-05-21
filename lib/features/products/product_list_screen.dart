import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'product_form_screen.dart';
import 'category_screen.dart';

// ============================================================
// PRODUCT LIST SCREEN – Danh sách kho cây
// Hiển thị cây + tồn kho, tìm kiếm, lọc theo loại
// ============================================================

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final _db = Supabase.instance.client;
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _variants = [];
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;
  String _search = '';
  String? _selectedCategoryId; // null = tất cả

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Load categories
      final catRes =
          await _db.from('categories').select('id, name').order('name');
      _categories = List<Map<String, dynamic>>.from(catRes);

      // Load variants + join product + category
      final varRes = await _db
          .from('product_variants')
          .select('''
        id, variant_name, sku, base_price, cost_price,
        stock_quantity, is_active, thumbnail_url, image_url,
        products(id, product_name, category_id,
          categories(id, name))
      ''')
          .eq('is_active', true)
          .isFilter('deleted_at', null)
          .order('variant_name');

      setState(() => _variants = List<Map<String, dynamic>>.from(varRes));
    } catch (e) {
      _showError('Lỗi tải danh sách: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── Filter theo search + category ───────────────────────
  List<Map<String, dynamic>> get _filtered {
    return _variants.where((v) {
      final name = (v['variant_name'] as String? ?? '').toLowerCase();
      final pname = ((v['products'] as Map?)?['product_name'] as String? ?? '')
          .toLowerCase();
      final sku = (v['sku'] as String? ?? '').toLowerCase();
      final q = _search.toLowerCase();

      final matchSearch =
          q.isEmpty || name.contains(q) || pname.contains(q) || sku.contains(q);

      final catId = (v['products'] as Map?)?['category_id'] as String?;
      final matchCat =
          _selectedCategoryId == null || catId == _selectedCategoryId;

      return matchSearch && matchCat;
    }).toList();
  }

  // Tổng tồn kho
  int get _totalStock =>
      _variants.fold(0, (s, v) => s + ((v['stock_quantity'] as int?) ?? 0));

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFFFF3B30),
          behavior: SnackBarBehavior.floating),
    );
  }

  void _openForm({Map<String, dynamic>? variant}) {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => ProductFormScreen(variant: variant),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F2F7),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Kho cây',
          style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5),
        ),
        actions: [
          // Tổng tồn kho
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF34C759).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$_totalStock cây',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF34C759),
              ),
            ),
          ),
          // Danh mục
          IconButton(
            onPressed: () => Navigator.push(
              context,
              CupertinoPageRoute(builder: (_) => const CategoryScreen()),
            ).then((_) => _load()),
            icon: const Icon(CupertinoIcons.tag, size: 20),
            tooltip: 'Danh mục',
          ),
          // Thêm mới
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: () => _openForm(),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: CupertinoSearchTextField(
                  controller: _searchCtrl,
                  placeholder: 'Tìm tên cây, SKU...',
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              // Category filter
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _CatChip(
                      label: 'Tất cả',
                      selected: _selectedCategoryId == null,
                      onTap: () => setState(() => _selectedCategoryId = null),
                    ),
                    ..._categories.map((c) => _CatChip(
                          label: c['name'] as String,
                          selected: _selectedCategoryId == c['id'],
                          onTap: () => setState(
                              () => _selectedCategoryId = c['id'] as String),
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : filtered.isEmpty
              ? _EmptyState(onAdd: () => _openForm())
              : RefreshIndicator.adaptive(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) => _ProductCard(
                      variant: filtered[i],
                      onTap: () => _openForm(variant: filtered[i]),
                    ),
                  ),
                ),
    );
  }
}

// ── Category chip ────────────────────────────────────────────
class _CatChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CatChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF34C759) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.grey.shade600,
            ),
          ),
        ),
      );
}

// ── Product Card ─────────────────────────────────────────────
class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> variant;
  final VoidCallback onTap;
  const _ProductCard({required this.variant, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = variant['variant_name'] as String? ?? '';
    final sku = variant['sku'] as String? ?? '';
    final stock = variant['stock_quantity'] as int? ?? 0;
    final price = (variant['base_price'] as num?)?.toDouble() ?? 0;
    final cost = (variant['cost_price'] as num?)?.toDouble() ?? 0;
    final imageUrl =
        variant['thumbnail_url'] as String? ?? variant['image_url'] as String?;
    final catName = ((variant['products'] as Map?)?['categories']
        as Map?)?['name'] as String?;

    final profit = price - cost;
    final isLowStock = stock <= 3;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Ảnh cây
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: imageUrl != null && imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _PlaceholderImg(),
                          errorWidget: (_, __, ___) => _PlaceholderImg(),
                        )
                      : _PlaceholderImg(),
                ),
                const SizedBox(width: 12),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Tồn kho badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isLowStock
                                  ? const Color(0xFFFF3B30).withOpacity(0.1)
                                  : const Color(0xFF34C759).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$stock cây',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isLowStock
                                    ? const Color(0xFFFF3B30)
                                    : const Color(0xFF34C759),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (catName != null)
                            Text(
                              catName,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade500),
                            ),
                          if (catName != null && sku.isNotEmpty)
                            Text(' · ',
                                style: TextStyle(color: Colors.grey.shade300)),
                          if (sku.isNotEmpty)
                            Text(
                              'SKU: $sku',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade400),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            _fmt(price),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF007AFF),
                            ),
                          ),
                          if (cost > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              'Lãi: ${_fmt(profit)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: profit >= 0
                                    ? const Color(0xFF34C759)
                                    : const Color(0xFFFF3B30),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(CupertinoIcons.chevron_right,
                    size: 15, color: Colors.grey.shade300),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M đ';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k đ';
    return '${v.toStringAsFixed(0)} đ';
  }
}

class _PlaceholderImg extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 56,
        height: 56,
        color: Colors.green.shade50,
        child: const Center(child: Text('🌱', style: TextStyle(fontSize: 26))),
      );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🌿', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            const Text('Kho cây trống',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Thêm cây đầu tiên vào kho',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(CupertinoIcons.add, size: 16),
              label: const Text('Thêm cây'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF34C759),
                minimumSize: const Size(160, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      );
}

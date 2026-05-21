// plant_picker_sheet.dart
// Bottom sheet chọn cây từ kho — mở từ CreateOrderSheet
// Tách riêng vì danh sách dài, có search, logic riêng biệt

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'live_order_ui.dart';

class PlantPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> products;
  final ValueChanged<Map<String, dynamic>> onSelect;

  const PlantPickerSheet({
    super.key,
    required this.products,
    required this.onSelect,
  });

  /// Mở sheet — gọi từ ngoài
  static void show(
    BuildContext context, {
    required List<Map<String, dynamic>> products,
    required ValueChanged<Map<String, dynamic>> onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlantPickerSheet(products: products, onSelect: onSelect),
    );
  }

  @override
  State<PlantPickerSheet> createState() => _PlantPickerSheetState();
}

class _PlantPickerSheetState extends State<PlantPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return widget.products;
    final q = _query.toLowerCase();
    return widget.products.where((p) {
      final name = (p['variant_name'] as String? ?? '').toLowerCase();
      final sku = (p['sku'] as String? ?? '').toLowerCase();
      return name.contains(q) || sku.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(children: [
          const SheetHandle(),

          // ── Header ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 16, 10),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: kGreen.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: const Center(
                    child: Text('🌱', style: TextStyle(fontSize: 18))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Chọn cây từ kho',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3)),
                    Text('${filtered.length} cây còn hàng',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              SheetCloseButton(onTap: () => Navigator.pop(context)),
            ]),
          ),

          // ── Search bar ───────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: CupertinoSearchTextField(
              controller: _searchCtrl,
              placeholder: 'Tìm tên cây, SKU...',
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 6),

          // ── List cây ────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🪴', style: TextStyle(fontSize: 40)),
                        const SizedBox(height: 10),
                        Text('Không tìm thấy cây nào',
                            style: TextStyle(
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _PlantItem(
                        product: filtered[i],
                        onTap: () {
                          Navigator.pop(context);
                          widget.onSelect(filtered[i]);
                        }),
                  ),
          ),
        ]),
      ),
    );
  }
}

// ── Item cây trong danh sách ──────────────────────────────────
class _PlantItem extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onTap;

  const _PlantItem({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = product['variant_name'] as String? ?? '';
    final price = (product['base_price'] as num?)?.toDouble() ?? 0;
    final stock = product['stock_quantity'] as int? ?? 0;
    final sku = product['sku'] as String? ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
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
        child: Row(children: [
          // Thumbnail / icon
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12)),
            child:
                const Center(child: Text('🌱', style: TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(children: [
                  // Badge tồn kho
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: stock > 3
                          ? kGreen.withOpacity(0.1)
                          : kRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Tồn: $stock',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: stock > 3 ? kGreen : kRed)),
                  ),
                  if (sku.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text('SKU: $sku',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ]),
              ],
            ),
          ),
          // Giá + chevron
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${fmtMoney(price)}đ',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: kBlue)),
            const SizedBox(height: 4),
            const Icon(CupertinoIcons.chevron_right,
                size: 14, color: Colors.grey),
          ]),
        ]),
      ),
    );
  }
}

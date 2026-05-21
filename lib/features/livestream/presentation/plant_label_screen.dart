// plant_label_screen.dart
// Màn hình xem trước + in phiếu dán cây
// Tách riêng khỏi CreateOrderSheet vì đây là bước cuối độc lập

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gua_pos/features/livestream/data/order_result_model.dart';
import 'live_order_ui.dart';

class PlantLabelScreen extends StatelessWidget {
  final OrderResult result;
  final VoidCallback onDone;
  final VoidCallback onAddAnotherPlant; // chốt thêm cây khác cho khách

  const PlantLabelScreen({
    super.key,
    required this.result,
    required this.onDone,
    required this.onAddAnotherPlant,
  });

  // ── Gửi lệnh in Bluetooth ────────────────────────────────────
  // TODO: thay bằng flutter_bluetooth_printer
  void _printLabel(BuildContext context) {
    final raw = result.buildRawPrintText();
    debugPrint('=== RAW PRINT ===\n$raw');

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('🖨️ Đã gửi lệnh in phiếu'),
      backgroundColor: kGreen,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(children: [
        const SheetHandle(),

        // ── Header ────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 16, 6),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: kGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: const Center(
                  child: Text('🖨️', style: TextStyle(fontSize: 18))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Phiếu dán cây',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4)),
                  Text(
                      result.isMerged
                          ? 'Đã gộp vào đơn cũ ✓'
                          : 'Đơn mới tạo thành công ✓',
                      style: const TextStyle(
                          fontSize: 12,
                          color: kGreen,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            SheetCloseButton(onTap: onDone),
          ]),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            child: Column(children: [
              // ── Preview phiếu ───────────────────────
              _LabelPreview(result: result),
              const SizedBox(height: 20),

              // ── IN NGAY ─────────────────────────────
              GradientButton(
                label: '🖨️  In phiếu ngay',
                colors: const [Color(0xFFFF9F0A), Color(0xFFFF3B30)],
                icon: CupertinoIcons.printer_fill,
                onTap: () => _printLabel(context),
              ),
              const SizedBox(height: 10),

              // ── In lại ──────────────────────────────
              _OutlineBtn(
                icon: CupertinoIcons.arrow_clockwise,
                label: 'In lại phiếu',
                onTap: () => _printLabel(context),
                borderColor: Colors.grey.shade300,
                foreground: Colors.grey.shade600,
              ),
              const SizedBox(height: 10),

              // ── Chốt thêm cây khác ───────────────────
              _OutlineBtn(
                icon: CupertinoIcons.add_circled,
                label: 'Chốt thêm cây khác cho khách này',
                onTap: onAddAnotherPlant,
                borderColor: kBlue,
                foreground: kBlue,
              ),
              const SizedBox(height: 10),

              // ── Quay lại live ────────────────────────
              FilledButton(
                onPressed: onDone,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: Colors.grey.shade700,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('Xong — Quay lại live',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ── Preview phiếu dán (giống máy in nhiệt) ───────────────────
class _LabelPreview extends StatelessWidget {
  final OrderResult r;
  const _LabelPreview({required OrderResult result}) : r = result;

  @override
  Widget build(BuildContext context) {
    final dt = r.createdAt;
    final timeStr =
        '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(children: [
        // Header gradient
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [kGreen, kBlue],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(children: [
            const Text('🌺 NHÀ VƯỜN ORCHID',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5)),
            const SizedBox(height: 2),
            Text('PHIẾU ĐỊNH DANH CÂY',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 11,
                    letterSpacing: 1.0)),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            // ── Tên cây + đặc điểm ──────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CÂY CHỐT',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 4),
                  Text(r.productName,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                          color: Color(0xFF1C1C1E))),

                  // Đặc điểm riêng của cây — QUAN TRỌNG để tránh nhầm
                  if (r.note.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                          color: kOrange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6)),
                      child: Row(children: [
                        const Icon(CupertinoIcons.tag,
                            size: 13, color: kOrange),
                        const SizedBox(width: 5),
                        Flexible(
                            child: Text(r.note,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: kOrange,
                                    fontWeight: FontWeight.w700))),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Giá
            _Row(
                icon: CupertinoIcons.money_dollar_circle_fill,
                iconColor: kRed,
                label: 'Giá cây',
                value: '${fmtMoney(r.price)} đ',
                valueColor: kRed,
                valueBold: true),
            _Divider(),

            // Khách
            _Row(
                icon: CupertinoIcons.person_fill,
                iconColor: kBlue,
                label: 'Khách hàng',
                value: r.customerName),
            _Divider(),
            _Row(
                icon: CupertinoIcons.phone_fill,
                iconColor: kGreen,
                label: 'Số điện thoại',
                value: r.phone,
                valueColor: kBlue,
                valueBold: true),
            _Divider(),

            // Ship
            _Row(
                icon: CupertinoIcons.cube_box_fill,
                iconColor: kOrange,
                label: 'Phí ship',
                value: '${fmtMoney(r.ship)} đ'),
            _Divider(),

            // Mã định danh cây
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(CupertinoIcons.barcode,
                    size: 16, color: Colors.white54),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('MÃ CÂY',
                          style: TextStyle(
                              fontSize: 9,
                              color: Colors.white54,
                              letterSpacing: 1.0)),
                      Text(r.labelCode,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 2.0)),
                    ],
                  ),
                ),
                // Platform badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: r.platform == 'tiktok'
                          ? const Color(0xFFFF0050)
                          : const Color(0xFF1877F2),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(r.platform.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w800)),
                ),
              ]),
            ),

            const SizedBox(height: 10),

            // Ngày giờ + đơn
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(timeStr,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                Text(r.orderCode,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: kBlue)),
              ],
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color? valueColor;
  final bool valueBold;

  const _Row({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.valueColor,
    this.valueBold = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Icon(icon, size: 15, color: iconColor),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: valueBold ? FontWeight.w800 : FontWeight.w600,
                  color: valueColor ?? const Color(0xFF1C1C1E))),
        ]),
      );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: Colors.grey.shade100);
}

class _OutlineBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color borderColor;
  final Color foreground;

  const _OutlineBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.borderColor,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: borderColor, width: 1.5),
          foregroundColor: foreground,
        ),
        icon: Icon(icon, size: 15),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
}

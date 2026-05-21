// order_result_model.dart
// Model chứa kết quả sau khi chốt đơn — dùng để render phiếu dán cây

class OrderResult {
  final String orderId;
  final String orderCode;
  final String detailId;
  final String customerName;
  final String phone;
  final String productName;
  final String sku;
  final double price;
  final double ship;
  final String note; // đặc điểm cây — in lên phiếu
  final String platform;
  final bool isMerged;
  final DateTime createdAt;

  const OrderResult({
    required this.orderId,
    required this.orderCode,
    required this.detailId,
    required this.customerName,
    required this.phone,
    required this.productName,
    required this.sku,
    required this.price,
    required this.ship,
    required this.note,
    required this.platform,
    required this.isMerged,
    required this.createdAt,
  });

  /// Mã định danh in lên phiếu: ưu tiên SKU, fallback detailId prefix
  String get labelCode =>
      sku.isNotEmpty ? sku : detailId.substring(0, 8).toUpperCase();

  /// Raw text gửi máy in nhiệt 58mm
  String buildRawPrintText() {
    final dt = createdAt;
    final timeStr =
        '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';

    return '''
================================
  NHA VUON ORCHID - PHIEU CAY
================================
CAY   : $productName
GIA   : ${_fmt(price)} d
================================
KHACH : $customerName
SDT   : $phone
SHIP  : ${_fmt(ship)} d
================================
${note.isNotEmpty ? 'DAC DIEM:\n$note\n================================' : ''}
DON   : $orderCode
MA CAY: $labelCode
NGAY  : $timeStr
================================
[${isMerged ? 'GOP DON' : 'DON MOI'}] ${platform.toUpperCase()}
================================


''';
  }

  static String _fmt(double v) => v.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
}

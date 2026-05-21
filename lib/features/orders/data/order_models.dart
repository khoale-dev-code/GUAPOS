import 'dart:ui';

// ============================================================
// ORDER MODELS - BẢN NÂNG CẤP
// ============================================================

class Order {
  final String id;
  final String? orderCode;
  final String? customerName;
  final String? phone;
  final String status;
  final double? finalAmount; // Tổng tiền (sau khi cộng ship, trừ giảm giá)
  final double? shippingFee;
  final String? notes; // Dùng để lưu cả địa chỉ giao hàng
  final String? platform;
  final String? sessionId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<OrderItem> items;

  // ── THUỘC TÍNH MỞ RỘNG (Gợi ý cho app POS) ─────────────────
  final String? paymentMethod; // Tiền mặt, Chuyển khoản, COD
  final double? discount; // Giảm giá thủ công

  const Order({
    required this.id,
    this.orderCode,
    this.customerName,
    this.phone,
    required this.status,
    this.finalAmount,
    this.shippingFee,
    this.notes,
    this.platform,
    this.sessionId,
    required this.createdAt,
    this.updatedAt,
    this.items = const [],
    this.paymentMethod,
    this.discount,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['order_details'] as List? ?? [];
    return Order(
      id: json['id'] as String,
      orderCode: json['order_code'] as String?,
      customerName: json['customer_name'] as String?,
      phone: json['phone'] as String?,
      status: json['status'] as String? ?? 'DRAFT',
      finalAmount: (json['final_amount'] as num?)?.toDouble(),
      shippingFee: (json['shipping_fee'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
      platform: json['platform'] as String?,
      sessionId: json['session_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      items: itemsRaw.map((e) => OrderItem.fromJson(e)).toList(),
      paymentMethod: json['payment_method'] as String?,
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
    );
  }

  // Logic hiển thị trạng thái chuẩn thương mại
  String get statusLabel {
    return switch (status) {
      'DRAFT' => 'Chờ xử lý',
      'CONFIRMED' => 'Đã xác nhận',
      'SHIPPING' => 'Đang giao',
      'DONE' => 'Hoàn thành',
      'CANCELLED' => 'Đã huỷ',
      _ => status
    };
  }

  Color get statusColor {
    return switch (status) {
      'DRAFT' => const Color(0xFFFF9F0A),
      'CONFIRMED' => const Color(0xFF007AFF),
      'SHIPPING' => const Color(0xFF5E5CE6),
      'DONE' => const Color(0xFF34C759),
      'CANCELLED' => const Color(0xFFFF3B30),
      _ => const Color(0xFF8E8E93)
    };
  }

  String get platformEmoji {
    return switch (platform) {
      'tiktok' => '🎵',
      'facebook' => '📘',
      'zalo' => '💬',
      'store' => '🏪',
      _ => '🛒'
    };
  }

  // Tính toán lại subtotal từ danh sách item (dùng khi hiển thị)
  double get subtotal => items.fold(0, (sum, i) => sum + i.totalPrice);

  // Tính tổng thực tế (Dùng nếu DB không tự tính)
  double get totalToPay => (subtotal + (shippingFee ?? 0) - (discount ?? 0));

  Order copyWith({
    String? status,
    List<OrderItem>? items,
    String? notes,
    double? shippingFee,
  }) =>
      Order(
        id: id,
        orderCode: orderCode,
        customerName: customerName,
        phone: phone,
        status: status ?? this.status,
        finalAmount: finalAmount,
        shippingFee: shippingFee ?? this.shippingFee,
        notes: notes ?? this.notes,
        platform: platform,
        sessionId: sessionId,
        createdAt: createdAt,
        updatedAt: updatedAt,
        items: items ?? this.items,
        paymentMethod: paymentMethod,
        discount: discount,
      );
}

// ────────────────────────────────────────────────────────────

class OrderItem {
  final String id;
  final String orderId;
  final String? variantId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  const OrderItem({
    required this.id,
    required this.orderId,
    this.variantId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    // Join dữ liệu từ bảng liên quan
    final variant = json['product_variants'] as Map<String, dynamic>?;
    final product = variant?['products'] as Map<String, dynamic>?;
    final name = variant?['variant_name'] as String? ??
        product?['product_name'] as String? ??
        'Sản phẩm';

    return OrderItem(
      id: json['id'] as String,
      orderId: json['order_id'] as String? ?? '',
      variantId: json['variant_id'] as String?,
      productName: name,
      quantity: json['quantity'] as int? ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0,
    );
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';
import 'order_models.dart';

class OrdersRepository {
  final _db = Supabase.instance.client;

  // ── Lấy danh sách đơn (Sử dụng Join SQL chuẩn) ──────────
  Future<List<Order>> getOrders({
    String? status,
    String? sessionId,
    int limit = 50,
  }) async {
    var query = _db.from('orders').select('''
          id, order_code, customer_name, phone, status,
          final_amount, shipping_fee, notes, platform,
          session_id, created_at, updated_at,
          order_details(
            id, order_id, variant_id, quantity, unit_price, total_price,
            product_variants(variant_name, products(product_name))
          )
        ''').isFilter('deleted_at', null);

    if (status != null) query = query.eq('status', status);
    if (sessionId != null) query = query.eq('session_id', sessionId);

    final res = await query.order('created_at', ascending: false).limit(limit);

    return (res as List).map((e) => Order.fromJson(e)).toList();
  }

  // ── Cập nhật trạng thái đơn (Có kiểm tra lỗi) ──────────
  Future<void> updateStatus(String orderId, String newStatus) async {
    try {
      await _db.from('orders').update({
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', orderId);

      // Log trạng thái
      await _db.from('order_status_logs').insert({
        'order_id': orderId,
        'new_status': newStatus,
      });
    } catch (e) {
      throw Exception('Lỗi chuyển trạng thái: $e');
    }
  }

  // ── Xác nhận hàng loạt (Dùng cho tính năng Chốt đơn) ────
  Future<void> confirmMany(List<String> orderIds) async {
    for (final id in orderIds) {
      await updateStatus(id, 'CONFIRMED');
    }
  }

  // ── Xoá sản phẩm khỏi đơn (Tự động trigger tính lại tiền) ─
  Future<Order> deleteItem(String itemId, String orderId) async {
    // 1. Xoá detail
    await _db.from('order_details').delete().eq('id', itemId);

    // 2. Cập nhật updated_at để Database tự tính lại Generated Column (final_amount)
    await _db.from('orders').update({
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', orderId);

    // 3. Tải lại đơn hàng mới nhất từ DB để UI update số tiền
    return _fetchOrderById(orderId);
  }

  // ── Cập nhật thông tin đơn (Địa chỉ, phí ship) ──────────
  Future<Order> updateOrder(
    String orderId, {
    String? notes,
    double? shippingFee,
    String? customerName,
  }) async {
    final data = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (notes != null) data['notes'] = notes;
    if (shippingFee != null) data['shipping_fee'] = shippingFee;
    if (customerName != null) data['customer_name'] = customerName;

    // Supabase tự tính toán final_amount dựa trên ship fee mới
    await _db.from('orders').update(data).eq('id', orderId);

    return _fetchOrderById(orderId);
  }

  // ── Hàm tiện ích: Tải lại đơn ──────────────────────────
  Future<Order> _fetchOrderById(String orderId) async {
    final res = await _db.from('orders').select('''
          id, order_code, customer_name, phone, status,
          final_amount, shipping_fee, notes, platform,
          session_id, created_at, updated_at,
          order_details(
            id, order_id, variant_id, quantity, unit_price, total_price,
            product_variants(variant_name, products(product_name))
          )
        ''').eq('id', orderId).single();
    return Order.fromJson(res);
  }

  Future<void> cancelOrder(String orderId) async {
    await updateStatus(orderId, 'CANCELLED');
  }
}

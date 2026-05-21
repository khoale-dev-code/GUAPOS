import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// REPORTS SCREEN – Báo cáo doanh thu & lợi nhuận
// Đơn giản, thực tế cho nhà vườn nhỏ 2–3 người
// ============================================================

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  String _period = 'today'; // 'today' | 'week' | 'month'

  // Số liệu tổng hợp
  double _totalRevenue = 0;
  double _totalShip = 0;
  double _totalCost = 0;
  int _totalOrders = 0;
  int _doneOrders = 0;

  // Top sản phẩm bán chạy
  List<Map<String, dynamic>> _topProducts = [];

  // Doanh thu theo ngày (7 ngày gần nhất)
  List<_DayData> _dailyRevenue = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime get _fromDate {
    final now = DateTime.now();
    switch (_period) {
      case 'week':
        return now.subtract(const Duration(days: 7));
      case 'month':
        return DateTime(now.year, now.month, 1);
      default: // today
        return DateTime(now.year, now.month, now.day);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await Future.wait([
        _loadSummary(),
        _loadTopProducts(),
        _loadDailyRevenue(),
      ]);
    } catch (e) {
      debugPrint('Lỗi báo cáo: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── Tổng hợp đơn hàng ───────────────────────────────────
  Future<void> _loadSummary() async {
    final from = _fromDate.toIso8601String();

    final res = await _db
        .from('orders')
        .select(
            'status, final_amount, shipping_fee, order_details(unit_price, quantity, product_variants(cost_price))')
        .neq('status', 'CANCELLED')
        .isFilter('deleted_at', null)
        .gte('created_at', from);

    double revenue = 0, ship = 0, cost = 0;
    int total = 0, done = 0;

    for (final order in res as List) {
      total++;
      if (order['status'] == 'DONE') done++;

      revenue += (order['final_amount'] as num?)?.toDouble() ?? 0;
      ship += (order['shipping_fee'] as num?)?.toDouble() ?? 0;

      for (final item in (order['order_details'] as List? ?? [])) {
        final qty = (item['quantity'] as int?) ?? 1;
        final costPrice =
            ((item['product_variants'] as Map?)?['cost_price'] as num?)
                    ?.toDouble() ??
                0;
        cost += costPrice * qty;
      }
    }

    setState(() {
      _totalRevenue = revenue;
      _totalShip = ship;
      _totalCost = cost;
      _totalOrders = total;
      _doneOrders = done;
    });
  }

  // ── Top sản phẩm bán chạy ───────────────────────────────
  Future<void> _loadTopProducts() async {
    final from = _fromDate.toIso8601String();

    // Lấy order_details join qua orders để filter theo ngày
    final res = await _db.from('order_details').select('''
          quantity, unit_price, total_price,
          product_variants(variant_name, cost_price),
          orders!inner(created_at, status)
        ''').neq('orders.status', 'CANCELLED').gte('orders.created_at', from);

    // Gom nhóm theo tên sản phẩm
    final Map<String, _ProductStat> map = {};
    for (final item in res as List) {
      final variant = item['product_variants'] as Map?;
      final name = variant?['variant_name'] as String? ?? 'Không tên';
      final qty = (item['quantity'] as int?) ?? 1;
      final revenue = (item['total_price'] as num?)?.toDouble() ?? 0;
      final cost = ((variant?['cost_price'] as num?)?.toDouble() ?? 0) * qty;

      if (map.containsKey(name)) {
        map[name]!.qty += qty;
        map[name]!.revenue += revenue;
        map[name]!.cost += cost;
      } else {
        map[name] =
            _ProductStat(name: name, qty: qty, revenue: revenue, cost: cost);
      }
    }

    // Sort theo số lượng bán
    final sorted = map.values.toList()..sort((a, b) => b.qty.compareTo(a.qty));
    setState(
        () => _topProducts = sorted.take(10).map((s) => s.toMap()).toList());
  }

  // ── Doanh thu 7 ngày ────────────────────────────────────
  Future<void> _loadDailyRevenue() async {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 6));

    final res = await _db
        .from('orders')
        .select('created_at, final_amount')
        .neq('status', 'CANCELLED')
        .isFilter('deleted_at', null)
        .gte('created_at',
            DateTime(from.year, from.month, from.day).toIso8601String());

    // Gom theo ngày
    final Map<String, double> dayMap = {};
    for (int i = 0; i < 7; i++) {
      final d = now.subtract(Duration(days: 6 - i));
      final key = '${d.day}/${d.month}';
      dayMap[key] = 0;
    }

    for (final order in res as List) {
      final dt = DateTime.parse(order['created_at'] as String).toLocal();
      final key = '${dt.day}/${dt.month}';
      if (dayMap.containsKey(key)) {
        dayMap[key] = (dayMap[key] ?? 0) +
            ((order['final_amount'] as num?)?.toDouble() ?? 0);
      }
    }

    setState(() {
      _dailyRevenue = dayMap.entries
          .map((e) => _DayData(label: e.key, amount: e.value))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final profit = _totalRevenue - _totalShip - _totalCost;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F2F7),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Báo cáo',
          style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5),
        ),
        actions: [
          IconButton(
              onPressed: _load,
              icon: const Icon(CupertinoIcons.refresh, size: 20)),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: _PeriodBar(
            selected: _period,
            onChanged: (p) {
              setState(() => _period = p);
              _load();
            },
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : RefreshIndicator.adaptive(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── KPI Cards ──
                  _KpiRow(
                    items: [
                      _KpiItem(
                        label: 'Doanh thu',
                        value: _fmt(_totalRevenue),
                        icon: CupertinoIcons.money_dollar_circle_fill,
                        color: const Color(0xFF007AFF),
                      ),
                      _KpiItem(
                        label: 'Lợi nhuận',
                        value: _fmt(profit),
                        icon: CupertinoIcons.chart_bar_fill,
                        color: profit >= 0
                            ? const Color(0xFF34C759)
                            : const Color(0xFFFF3B30),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _KpiRow(
                    items: [
                      _KpiItem(
                        label: 'Tổng đơn',
                        value: _totalOrders.toString(),
                        icon: CupertinoIcons.doc_text_fill,
                        color: const Color(0xFF5E5CE6),
                      ),
                      _KpiItem(
                        label: 'Hoàn thành',
                        value: _doneOrders.toString(),
                        icon: CupertinoIcons.checkmark_seal_fill,
                        color: const Color(0xFF34C759),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Chi tiết tài chính ──
                  _SectionLabel(label: 'Chi tiết'),
                  _FinanceCard(
                    revenue: _totalRevenue,
                    ship: _totalShip,
                    cost: _totalCost,
                    profit: profit,
                  ),
                  const SizedBox(height: 16),

                  // ── Biểu đồ 7 ngày ──
                  if (_dailyRevenue.isNotEmpty) ...[
                    _SectionLabel(label: 'Doanh thu 7 ngày gần nhất'),
                    _BarChart(data: _dailyRevenue),
                    const SizedBox(height: 16),
                  ],

                  // ── Top sản phẩm ──
                  if (_topProducts.isNotEmpty) ...[
                    _SectionLabel(label: 'Cây bán chạy'),
                    ..._topProducts.asMap().entries.map((e) => _TopProductRow(
                          rank: e.key + 1,
                          data: e.value,
                        )),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  String _fmt(double v) {
    if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M đ';
    if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(0)}k đ';
    return '${v.toStringAsFixed(0)} đ';
  }
}

// ============================================================
// COMPONENTS
// ============================================================

class _PeriodBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _PeriodBar({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              for (final tab in [
                ('today', 'Hôm nay'),
                ('week', '7 ngày'),
                ('month', 'Tháng này')
              ])
                Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(tab.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: selected == tab.$1
                            ? Colors.white
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: selected == tab.$1
                            ? [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 4)
                              ]
                            : [],
                      ),
                      child: Center(
                        child: Text(
                          tab.$2,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected == tab.$1
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected == tab.$1
                                ? Colors.black
                                : Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
              letterSpacing: 0.5),
        ),
      );
}

// ── KPI ─────────────────────────────────────────────────────
class _KpiRow extends StatelessWidget {
  final List<_KpiItem> items;
  const _KpiRow({required this.items});

  @override
  Widget build(BuildContext context) => Row(
        children: items
            .map((item) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                        right: item == items.first ? 5 : 0,
                        left: item == items.last ? 5 : 0),
                    child: item,
                  ),
                ))
            .toList(),
      );
}

class _KpiItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _KpiItem(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: -0.5),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
      );
}

// ── Finance detail ───────────────────────────────────────────
class _FinanceCard extends StatelessWidget {
  final double revenue, ship, cost, profit;
  const _FinanceCard(
      {required this.revenue,
      required this.ship,
      required this.cost,
      required this.profit});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            _Row(label: '💰 Doanh thu', value: _fmt(revenue), bold: false),
            _D(),
            _Row(label: '🚚 Tiền ship', value: '− ${_fmt(ship)}', bold: false),
            _D(),
            _Row(label: '📦 Giá vốn', value: '− ${_fmt(cost)}', bold: false),
            Divider(height: 1, color: Colors.grey.shade200),
            _Row(
              label: '📈 Lợi nhuận',
              value: _fmt(profit),
              bold: true,
              valueColor: profit >= 0
                  ? const Color(0xFF34C759)
                  : const Color(0xFFFF3B30),
            ),
          ],
        ),
      );

  String _fmt(double v) {
    if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M đ';
    if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(0)}k đ';
    return '${v.toStringAsFixed(0)} đ';
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  final bool bold;
  final Color? valueColor;
  const _Row(
      {required this.label,
      required this.value,
      required this.bold,
      this.valueColor});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                    color:
                        bold ? const Color(0xFF1C1C1E) : Colors.grey.shade600)),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: valueColor ?? const Color(0xFF1C1C1E))),
          ],
        ),
      );
}

class _D extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, indent: 16, color: Colors.grey.shade100);
}

// ── Bar Chart 7 ngày ─────────────────────────────────────────
class _BarChart extends StatelessWidget {
  final List<_DayData> data;
  const _BarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxVal = data.fold(0.0, (m, d) => d.amount > m ? d.amount : m);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: data.map((d) {
                final ratio = maxVal > 0 ? d.amount / maxVal : 0.0;
                final isToday =
                    d.label == '${DateTime.now().day}/${DateTime.now().month}';
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Giá trị
                        if (d.amount > 0)
                          Text(
                            d.amount >= 1000000
                                ? '${(d.amount / 1000000).toStringAsFixed(1)}M'
                                : '${(d.amount / 1000).toStringAsFixed(0)}k',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        const SizedBox(height: 2),
                        // Bar
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          height: ratio * 80 + (d.amount > 0 ? 4 : 0),
                          decoration: BoxDecoration(
                            color: isToday
                                ? const Color(0xFF007AFF)
                                : const Color(0xFF007AFF).withOpacity(0.3),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
          // Labels ngày
          Row(
            children: data.map((d) {
              final isToday =
                  d.label == '${DateTime.now().day}/${DateTime.now().month}';
              return Expanded(
                child: Text(
                  isToday ? 'HN' : d.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: isToday
                        ? const Color(0xFF007AFF)
                        : Colors.grey.shade400,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Top product row ──────────────────────────────────────────
class _TopProductRow extends StatelessWidget {
  final int rank;
  final Map<String, dynamic> data;
  const _TopProductRow({required this.rank, required this.data});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String;
    final qty = data['qty'] as int;
    final revenue = (data['revenue'] as num).toDouble();
    final profit = revenue - (data['cost'] as num).toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          // Rank
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: rank <= 3
                  ? const Color(0xFFFFD60A).withOpacity(0.15)
                  : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                rank <= 3 ? ['🥇', '🥈', '🥉'][rank - 1] : '$rank',
                style: TextStyle(
                    fontSize: rank <= 3 ? 14 : 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text('$qty cây bán ra',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fmt(revenue),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF007AFF)),
              ),
              Text(
                'Lãi: ${_fmt(profit)}',
                style: TextStyle(
                    fontSize: 11,
                    color: profit >= 0
                        ? const Color(0xFF34C759)
                        : const Color(0xFFFF3B30)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M đ';
    if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(0)}k đ';
    return '${v.toStringAsFixed(0)} đ';
  }
}

// ── Data classes ─────────────────────────────────────────────
class _DayData {
  final String label;
  final double amount;
  const _DayData({required this.label, required this.amount});
}

class _ProductStat {
  final String name;
  int qty;
  double revenue;
  double cost;

  _ProductStat(
      {required this.name,
      required this.qty,
      required this.revenue,
      required this.cost});

  Map<String, dynamic> toMap() =>
      {'name': name, 'qty': qty, 'revenue': revenue, 'cost': cost};
}

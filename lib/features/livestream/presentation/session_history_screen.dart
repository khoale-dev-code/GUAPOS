import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'session_detail_screen.dart';
import '../../../../shared/models/livestream_models.dart';

class SessionHistoryScreen extends StatefulWidget {
  const SessionHistoryScreen({super.key});

  @override
  State<SessionHistoryScreen> createState() => _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends State<SessionHistoryScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _allSessions = [];
  List<Map<String, dynamic>> _filtered = [];

  // Filters
  String _platform = 'all'; // 'all' | 'tiktok' | 'facebook'
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _toDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await _db
          .from('livestream_sessions')
          .select('id, title, platform, status, created_at, ended_at')
          .eq('status', 'ended')
          .order('created_at', ascending: false);
      _allSessions = List<Map<String, dynamic>>.from(res);
    } catch (_) {}
    _applyFilters();
    if (mounted) setState(() => _loading = false);
  }

  void _applyFilters() {
    final from = DateTime(_fromDate.year, _fromDate.month, _fromDate.day);
    final to = DateTime(_toDate.year, _toDate.month, _toDate.day, 23, 59, 59);

    _filtered = _allSessions.where((s) {
      if (_platform != 'all' && s['platform'] != _platform) return false;
      final created = DateTime.parse(s['created_at'] as String).toLocal();
      if (created.isBefore(from) || created.isAfter(to)) return false;
      return true;
    }).toList();
  }

  int get _totalOrders =>
      _filtered.fold(0, (sum, s) => sum + ((s['order_count'] as int?) ?? 0));

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : _toDate;
    final picked = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (_) => _DatePickerSheet(initial: initial),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
        if (_fromDate.isAfter(_toDate)) _toDate = picked;
      } else {
        _toDate = picked;
        if (_toDate.isBefore(_fromDate)) _fromDate = picked;
      }
      _applyFilters();
    });
  }

  LiveSession _toModel(Map<String, dynamic> d) => LiveSession(
        id: d['id'] as String,
        title: d['title'] as String? ?? 'Phiên Live',
        platform: d['platform'] as String? ?? 'tiktok',
        status: d['status'] as String? ?? 'ended',
        createdAt: DateTime.parse(d['created_at'] as String),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: const Icon(CupertinoIcons.back, color: Color(0xFF007AFF)),
        ),
        title: const Text(
          'Lịch sử phiên live',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: RefreshIndicator.adaptive(
        onRefresh: _fetch,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            // ── KPI CARDS ──
            _KpiRow(
              totalSessions: _filtered.length,
              totalOrders: _totalOrders,
            ),
            const SizedBox(height: 14),

            // ── FILTER CARD ──
            _FilterCard(
              platform: _platform,
              fromDate: _fromDate,
              toDate: _toDate,
              onPlatformChanged: (p) => setState(() {
                _platform = p;
                _applyFilters();
              }),
              onPickFrom: () => _pickDate(isFrom: true),
              onPickTo: () => _pickDate(isFrom: false),
            ),
            const SizedBox(height: 14),

            // ── RESULT LABEL ──
            _SectionLabel(
              label: 'Kết quả – ${_filtered.length} phiên',
            ),
            const SizedBox(height: 8),

            // ── LIST ──
            if (_loading)
              const _LoadingPlaceholder()
            else if (_filtered.isEmpty)
              const _EmptyState()
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final s = _filtered[i];
                  return _SessionRow(
                    data: s,
                    onTap: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => SessionDetailScreen(
                          session: _toModel(s),
                        ),
                      ),
                    ).then((_) => _fetch()),
                  );
                },
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// KPI ROW
// ─────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  final int totalSessions;
  final int totalOrders;
  const _KpiRow({required this.totalSessions, required this.totalOrders});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _KpiCard(label: 'Tổng phiên', value: '$totalSessions')),
        const SizedBox(width: 10),
        Expanded(child: _KpiCard(label: 'Tổng đơn', value: '$totalOrders')),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  const _KpiCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1C1C1E))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FILTER CARD
// ─────────────────────────────────────────────────────────────

class _FilterCard extends StatelessWidget {
  final String platform;
  final DateTime fromDate;
  final DateTime toDate;
  final ValueChanged<String> onPlatformChanged;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;

  const _FilterCard({
    required this.platform,
    required this.fromDate,
    required this.toDate,
    required this.onPlatformChanged,
    required this.onPickFrom,
    required this.onPickTo,
  });

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
      ),
      child: Column(
        children: [
          // Platform pills
          Row(
            children: [
              const SizedBox(
                width: 68,
                child: Text('Nền tảng',
                    style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
              ),
              _PlatformPill(
                label: 'Tất cả',
                active: platform == 'all',
                onTap: () => onPlatformChanged('all'),
              ),
              const SizedBox(width: 6),
              _PlatformPill(
                label: 'TikTok',
                icon: CupertinoIcons.play_circle,
                active: platform == 'tiktok',
                onTap: () => onPlatformChanged('tiktok'),
              ),
              const SizedBox(width: 6),
              _PlatformPill(
                label: 'Facebook',
                icon: CupertinoIcons.video_camera,
                active: platform == 'facebook',
                activeColor: const Color(0xFF1877F2),
                onTap: () => onPlatformChanged('facebook'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 12),
          // Date rows
          _DateRow(
            label: 'Từ ngày',
            value: _fmt(fromDate),
            onTap: onPickFrom,
          ),
          const SizedBox(height: 10),
          _DateRow(
            label: 'Đến ngày',
            value: _fmt(toDate),
            onTap: onPickTo,
          ),
        ],
      ),
    );
  }
}

class _PlatformPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;
  final Color activeColor;

  const _PlatformPill({
    required this.label,
    this.icon,
    required this.active,
    required this.onTap,
    this.activeColor = const Color(0xFF1C1C1E),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? activeColor : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? activeColor : const Color(0xFFE5E5EA),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 12,
                  color: active ? Colors.white : const Color(0xFF8E8E93)),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : const Color(0xFF3C3C43),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateRow(
      {required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 68,
          child: Text(label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
        ),
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
              ),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.calendar,
                      size: 14, color: Color(0xFF8E8E93)),
                  const SizedBox(width: 8),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1C1C1E))),
                  const Spacer(),
                  const Icon(CupertinoIcons.chevron_down,
                      size: 12, color: Color(0xFFC7C7CC)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SESSION ROW
// ─────────────────────────────────────────────────────────────

class _SessionRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _SessionRow({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isTikTok = data['platform'] == 'tiktok';
    final title = data['title'] as String? ?? 'Phiên Live';
    final createdAt = DateTime.parse(data['created_at'] as String).toLocal();
    final orders = (data['order_count'] as int?) ?? 0;
    final done = (data['done_count'] as int?) ?? 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
        ),
        child: Row(
          children: [
            // Platform icon
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isTikTok
                    ? const Color(0xFFF2F2F7)
                    : const Color(0xFFE6F1FB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isTikTok
                    ? CupertinoIcons.play_circle
                    : CupertinoIcons.video_camera,
                size: 18,
                color: isTikTok
                    ? const Color(0xFF1C1C1E)
                    : const Color(0xFF185FA5),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(
                    '${createdAt.day}/${createdAt.month}/${createdAt.year}'
                    ' · ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}'
                    ' · $done/$orders đơn xong',
                    style:
                        const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Order pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3DE),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$orders đơn',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF27500A)),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(CupertinoIcons.chevron_right,
                size: 14, color: Color(0xFFC7C7CC)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DATE PICKER SHEET
// ─────────────────────────────────────────────────────────────

class _DatePickerSheet extends StatefulWidget {
  final DateTime initial;
  const _DatePickerSheet({required this.initial});

  @override
  State<_DatePickerSheet> createState() => _DatePickerSheetState();
}

class _DatePickerSheetState extends State<_DatePickerSheet> {
  late DateTime _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CupertinoColors.systemBackground.resolveFrom(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: Color(0xFFE5E5EA), width: 0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: const Text('Huỷ',
                      style: TextStyle(color: Color(0xFF8E8E93))),
                  onPressed: () => Navigator.pop(context),
                ),
                const Text('Chọn ngày',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: const Text('Xong',
                      style: TextStyle(
                          color: Color(0xFF007AFF),
                          fontWeight: FontWeight.w600)),
                  onPressed: () => Navigator.pop(context, _picked),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 220,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.date,
              initialDateTime: _picked,
              maximumDate: DateTime.now(),
              minimumYear: 2020,
              onDateTimeChanged: (d) => _picked = d,
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SMALL WIDGETS
// ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF8E8E93),
          letterSpacing: 0.4,
        ),
      );
}

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
        ),
        child: const Center(child: CupertinoActivityIndicator()),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
        ),
        child: Column(
          children: [
            Icon(CupertinoIcons.tray, size: 36, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text(
              'Không có phiên nào khớp bộ lọc',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF3C3C43)),
            ),
            const SizedBox(height: 4),
            const Text(
              'Thử thay đổi khoảng ngày hoặc nền tảng.',
              style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
            ),
          ],
        ),
      );
}

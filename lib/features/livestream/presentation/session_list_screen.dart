import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../data/livestream_repository.dart';
import '../../../../shared/models/livestream_models.dart';
import 'live_comments_screen.dart';

// ============================================================
// SESSION LIST SCREEN
// Màn hình đầu tiên: chọn phiên live hoặc tạo mới
// ============================================================

class SessionListScreen extends StatefulWidget {
  const SessionListScreen({super.key});

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  final _repo = LivestreamRepository();
  List<LiveSession> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sessions = await _repo.getSessions();
      setState(() => _sessions = sessions);
    } catch (e) {
      _showError('Không tải được danh sách phiên: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── Tạo phiên live mới ───────────────────────────────────
  Future<void> _createSession(String platform) async {
    try {
      final session = await _repo.createSession(platform: platform);
      if (!mounted) return;
      _openComments(session);
      _load(); // refresh list
    } catch (e) {
      _showError('Không tạo được phiên: $e');
    }
  }

  void _openComments(LiveSession session) {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => LiveCommentsScreen(session: session),
      ),
    ).then((_) => _load()); // refresh khi quay lại
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  // ── Dialog chọn nền tảng ─────────────────────────────────
  void _showNewSessionDialog() {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Bắt đầu phiên Live mới'),
        message: const Text('Chọn nền tảng đang livestream'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _createSession('tiktok');
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('🎵  ', style: TextStyle(fontSize: 20)),
                Text('TikTok Live',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _createSession('facebook');
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('📘  ', style: TextStyle(fontSize: 20)),
                Text('Facebook Live',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Tách phiên đang live và lịch sử
    final liveSessions = _sessions.where((s) => s.isLive).toList();
    final pastSessions = _sessions.where((s) => !s.isLive).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F2F7),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Livestream',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          // Nút làm mới
          IconButton(
            onPressed: _load,
            icon: const Icon(CupertinoIcons.refresh, size: 20),
          ),
          // Nút tạo phiên mới
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _showNewSessionDialog,
              icon: const Icon(CupertinoIcons.add, size: 16),
              label: const Text('Phiên mới'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : RefreshIndicator.adaptive(
              onRefresh: _load,
              child: CustomScrollView(
                slivers: [
                  // ── Đang Live ──
                  if (liveSessions.isNotEmpty) ...[
                    _SectionHeader(
                      title: 'Đang Live',
                      badge: liveSessions.length.toString(),
                      badgeColor: const Color(0xFFFF3B30),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _SessionCard(
                          session: liveSessions[i],
                          onTap: () => _openComments(liveSessions[i]),
                        ),
                        childCount: liveSessions.length,
                      ),
                    ),
                  ],

                  // ── Lịch sử ──
                  if (pastSessions.isNotEmpty) ...[
                    _SectionHeader(title: 'Lịch sử phiên Live'),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _SessionCard(
                          session: pastSessions[i],
                          onTap: () => _openComments(pastSessions[i]),
                        ),
                        childCount: pastSessions.length,
                      ),
                    ),
                  ],

                  // ── Empty state ──
                  if (_sessions.isEmpty)
                    SliverFillRemaining(
                      child: _EmptyState(
                        onCreateTap: _showNewSessionDialog,
                      ),
                    ),

                  const SliverToBoxAdapter(
                    child: SizedBox(height: 32),
                  ),
                ],
              ),
            ),
    );
  }
}

// ============================================================
// COMPONENTS
// ============================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? badge;
  final Color? badgeColor;

  const _SectionHeader({
    required this.title,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Row(
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
                letterSpacing: 0.5,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor ?? const Color(0xFF007AFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Card phiên live ──────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  final LiveSession session;
  final VoidCallback onTap;

  const _SessionCard({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isLive = session.isLive;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Platform icon + live badge
                Stack(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isLive
                            ? const Color(0xFFFF3B30).withOpacity(0.1)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          session.platformEmoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    ),
                    if (isLive)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(width: 14),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (isLive)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF3B30),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'LIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              session.title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(session.createdAt),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      if (!isLive && (session.totalOrders ?? 0) > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _StatChip(
                              icon: CupertinoIcons.cart_fill,
                              label: '${session.totalOrders} đơn',
                              color: const Color(0xFF34C759),
                            ),
                            if (session.totalRevenue != null) ...[
                              const SizedBox(width: 6),
                              _StatChip(
                                icon: CupertinoIcons.money_dollar_circle_fill,
                                label: _formatMoney(session.totalRevenue!),
                                color: const Color(0xFF007AFF),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // Arrow
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatMoney(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    }
    return '${(amount / 1000).toStringAsFixed(0)}k';
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty State ──────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreateTap;
  const _EmptyState({required this.onCreateTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('📡', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          const Text(
            'Chưa có phiên Live nào',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Bấm "Phiên mới" để bắt đầu\nquản lý đơn hàng từ livestream',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey.shade500,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onCreateTap,
            icon: const Icon(CupertinoIcons.play_fill, size: 16),
            label: const Text('Tạo phiên Live'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              minimumSize: const Size(180, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'create_order_sheet.dart';
import 'lucky_wheel_screen.dart';
import 'live_comments_screen.dart';
import 'session_history_screen.dart';
import '../../../../shared/models/livestream_models.dart';

class LivestreamHubScreen extends StatefulWidget {
  const LivestreamHubScreen({super.key});

  @override
  State<LivestreamHubScreen> createState() => _LivestreamHubScreenState();
}

class _LivestreamHubScreenState extends State<LivestreamHubScreen> {
  final _db = Supabase.instance.client;

  int _selectedPlatformTab = 0;
  bool _loadingActive = true;

  Map<String, dynamic>? _activeSession;
  final List<LiveComment> _realtimeComments = [];

  RealtimeChannel? _commentSubscription;

  @override
  void initState() {
    super.initState();
    _loadPlatformData();
  }

  @override
  void dispose() {
    _cancelCommentSubscription();
    super.dispose();
  }

  String get _currentPlatform =>
      _selectedPlatformTab == 0 ? 'tiktok' : 'facebook';

  void _loadPlatformData() {
    _cancelCommentSubscription();
    setState(() => _realtimeComments.clear());
    _fetchActiveSession();
  }

  void _cancelCommentSubscription() {
    if (_commentSubscription != null) {
      _db.removeChannel(_commentSubscription!);
      _commentSubscription = null;
    }
  }

  Future<void> _fetchActiveSession() async {
    setState(() => _loadingActive = true);
    try {
      final res = await _db
          .from('livestream_sessions')
          .select('id, title, platform, status, stream_url, created_at')
          .eq('platform', _currentPlatform)
          .eq('status', 'live')
          .order('created_at', ascending: false)
          .limit(1);

      if ((res as List).isNotEmpty) {
        setState(() => _activeSession = res[0]);
        _listenToRealtimeComments(res[0]['id'] as String);
      } else {
        setState(() => _activeSession = null);
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingActive = false);
  }

  void _listenToRealtimeComments(String sessionId) {
    _commentSubscription = _db
        .channel('public:livestream_comments:$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'livestream_comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sessionId,
          ),
          callback: (payload) {
            final r = payload.newRecord;
            final comment = LiveComment(
              id: r['id']?.toString() ?? '',
              sessionId: sessionId,
              commenterName: r['commenter_name'] as String? ?? 'Khách ẩn danh',
              commentText: r['comment_text'] as String? ?? '',
              createdAt: DateTime.parse(r['created_at'] as String),
            );
            if (mounted) setState(() => _realtimeComments.insert(0, comment));
          },
        )..subscribe();
  }

  LiveSession _toModel(Map<String, dynamic> d) => LiveSession(
        id: d['id'] as String,
        title: d['title'] as String? ?? 'Phiên Live',
        platform: d['platform'] as String? ?? 'tiktok',
        status: d['status'] as String? ?? 'live',
        createdAt: d['created_at'] != null
            ? DateTime.parse(d['created_at'] as String)
            : DateTime.now(),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Trung tâm livestream',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _PlatformTabBar(
              selected: _selectedPlatformTab,
              onChanged: (i) {
                if (i == _selectedPlatformTab) return;
                setState(() => _selectedPlatformTab = i);
                _loadPlatformData();
              },
            ),
          ),
        ),
      ),
      body: RefreshIndicator.adaptive(
        onRefresh: () async => _loadPlatformData(),
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _SectionLabel(label: 'Phiên đang live'),
            const SizedBox(height: 6),
            _loadingActive
                ? const _LoadingCard()
                : _activeSession == null
                    ? _NoLiveCard(platform: _currentPlatform)
                    : _ActiveLiveCard(
                        session: _activeSession!,
                        comments: _realtimeComments,
                        onWheelTap: () => Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => LuckyWheelScreen(
                              session: _toModel(_activeSession!),
                            ),
                          ),
                        ),
                        onCommentTap: (comment) => showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => CreateOrderSheet(
                            comment: comment,
                            session: _toModel(_activeSession!),
                          ),
                        ),
                      ),
            const SizedBox(height: 20),
            _HistoryEntryButton(
              onTap: () => Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => const SessionHistoryScreen(),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PLATFORM TAB BAR
// ─────────────────────────────────────────────────────────────

class _PlatformTabBar extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _PlatformTabBar({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Tab(
          label: 'TikTok Live',
          icon: CupertinoIcons.play_circle,
          active: selected == 0,
          onTap: () => onChanged(0),
          activeColor: const Color(0xFF1C1C1E),
        ),
        const SizedBox(width: 10),
        _Tab(
          label: 'Facebook Live',
          icon: CupertinoIcons.video_camera,
          active: selected == 1,
          onTap: () => onChanged(1),
          activeColor: const Color(0xFF1877F2),
        ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final Color activeColor;

  const _Tab({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? activeColor : const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? activeColor : const Color(0xFFE5E5EA),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 14,
                  color: active ? Colors.white : Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ACTIVE LIVE CARD
// ─────────────────────────────────────────────────────────────

class _ActiveLiveCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final List<LiveComment> comments;
  final VoidCallback onWheelTap;
  final void Function(LiveComment) onCommentTap;

  const _ActiveLiveCard({
    required this.session,
    required this.comments,
    required this.onWheelTap,
    required this.onCommentTap,
  });

  static const List<Color> _avatarColors = [
    Color(0xFFE6F1FB),
    Color(0xFFEAF3DE),
    Color(0xFFEEEDFE),
    Color(0xFFFAEEDA),
  ];
  static const List<Color> _avatarTextColors = [
    Color(0xFF0C447C),
    Color(0xFF27500A),
    Color(0xFF3C3489),
    Color(0xFF633806),
  ];

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = comments
        .where((c) => RegExp(r'0[35789]\d{8}').hasMatch(c.commentText))
        .length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                _LiveBadge(),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    session['title'] as String? ?? 'Phiên Live',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Wheel button
                GestureDetector(
                  onTap: onWheelTap,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAEEDA),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFFF0CF9A), width: 0.5),
                    ),
                    child: const Icon(CupertinoIcons.gift,
                        size: 18, color: Color(0xFF854F0B)),
                  ),
                ),
              ],
            ),
          ),

          // Divider
          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // Comment list
          Container(
            height: 236,
            color: const Color(0xFFF9F9FB),
            child: comments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.chat_bubble_2,
                            size: 32, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text(
                          'Đang đợi bình luận từ live...',
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade400,
                              fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: comments.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 7),
                    itemBuilder: (ctx, i) {
                      final c = comments[i];
                      final colorIdx = i % _avatarColors.length;
                      return GestureDetector(
                        onTap: () => onCommentTap(c),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 9),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: const Color(0xFFE5E5EA), width: 0.5),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: _avatarColors[colorIdx],
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    _initials(c.commenterName),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: _avatarTextColors[colorIdx],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.commenterName,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF185FA5),
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      c.commentText,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF1C1C1E)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF3DE),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Chốt',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF27500A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: const BoxDecoration(
              border:
                  Border(top: BorderSide(color: Color(0xFFF0F0F0), width: 0.5)),
            ),
            child: Row(
              children: [
                Text(
                  '${comments.length} bình luận trong phiên',
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                ),
                const Spacer(),
                Row(
                  children: [
                    const Icon(CupertinoIcons.phone,
                        size: 12, color: Color(0xFF185FA5)),
                    const SizedBox(width: 4),
                    Text(
                      '$hasPhone có SĐT',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF185FA5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// HISTORY ENTRY BUTTON
// ─────────────────────────────────────────────────────────────

class _HistoryEntryButton extends StatelessWidget {
  final VoidCallback onTap;
  const _HistoryEntryButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
              ),
              child: const Icon(CupertinoIcons.time,
                  size: 20, color: Color(0xFF3C3C43)),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lịch sử phiên live',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Xem lại & chỉnh đơn hàng từ các phiên cũ',
                    style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                  ),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_right,
                size: 16, color: Color(0xFFC7C7CC)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SMALL COMPONENTS
// ─────────────────────────────────────────────────────────────

class _LiveBadge extends StatefulWidget {
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween(begin: 1.0, end: 0.3).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFF3B30),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: _anim,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoLiveCard extends StatelessWidget {
  final String platform;
  const _NoLiveCard({required this.platform});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
      ),
      child: Column(
        children: [
          Icon(CupertinoIcons.video_camera_solid,
              size: 38, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'Chưa có live trên ${platform == 'tiktok' ? 'TikTok' : 'Facebook'}',
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3C3C43)),
          ),
          const SizedBox(height: 6),
          const Text(
            'Khi bạn bật live, màn hình này sẽ tự động cập nhật.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
        ),
        child: const Center(child: CupertinoActivityIndicator()),
      );
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 0),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF8E8E93),
            letterSpacing: 0.5,
          ),
        ),
      );
}

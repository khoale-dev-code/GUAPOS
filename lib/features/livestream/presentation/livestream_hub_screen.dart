import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'create_order_sheet.dart';
import 'lucky_wheel_screen.dart';
import 'live_comments_screen.dart'; // Đảm bảo đã import file này
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
  bool _loadingHistory = true;

  Map<String, dynamic>? _activeSession;
  List<Map<String, dynamic>> _historySessions = [];
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

  String get _currentPlatformStr =>
      _selectedPlatformTab == 0 ? 'tiktok' : 'facebook';

  void _loadPlatformData() {
    _cancelCommentSubscription();
    _realtimeComments.clear();
    _fetchActiveSession();
    _fetchHistorySessions();
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
          .eq('platform', _currentPlatformStr)
          .eq('status', 'live')
          .order('created_at', ascending: false)
          .limit(1);

      if ((res as List).isNotEmpty) {
        setState(() {
          _activeSession = res[0];
        });
        _listenToRealtimeComments(res[0]['id'] as String);
      } else {
        setState(() => _activeSession = null);
      }
    } catch (_) {}
    setState(() => _loadingActive = false);
  }

  Future<void> _fetchHistorySessions() async {
    setState(() => _loadingHistory = true);
    try {
      final res = await _db
          .from('livestream_sessions')
          .select('id, title, platform, status, created_at, ended_at')
          .eq('platform', _currentPlatformStr)
          .eq('status', 'ended')
          .order('created_at', ascending: false);

      setState(() {
        _historySessions = List<Map<String, dynamic>>.from(res);
      });
    } catch (_) {}
    setState(() => _loadingHistory = false);
  }

  void _listenToRealtimeComments(String sessionId) {
    _commentSubscription =
        _db.channel('public:livestream_comments').onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'livestream_comments',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'session_id',
                value: sessionId,
              ),
              callback: (payload) {
                final newRecord = payload.newRecord;
                final comment = LiveComment(
                  id: newRecord['id']?.toString() ?? '',
                  sessionId: sessionId,
                  commenterName:
                      newRecord['commenter_name'] as String? ?? 'Khách ẩn danh',
                  commentText: newRecord['comment_text'] as String? ?? '',
                  createdAt: DateTime.parse(newRecord['created_at'] as String),
                );

                if (mounted) {
                  setState(() {
                    _realtimeComments.insert(0, comment);
                  });
                }
              },
            )..subscribe();
  }

  LiveSession _buildLiveSessionModel(Map<String, dynamic> sessionData) {
    return LiveSession(
      id: sessionData['id'] as String,
      title: sessionData['title'] as String? ?? 'Phiên Live',
      platform: sessionData['platform'] as String? ?? 'tiktok',
      status: sessionData['status'] as String? ?? 'live',
      createdAt: sessionData['created_at'] != null
          ? DateTime.parse(sessionData['created_at'] as String)
          : DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('Trung tâm Livestream',
            style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Row(
              children: [
                _PlatformTabButton(
                  label: '🎵 TikTok Live',
                  active: _selectedPlatformTab == 0,
                  onTap: () {
                    if (_selectedPlatformTab == 0) return;
                    setState(() => _selectedPlatformTab = 0);
                    _loadPlatformData();
                  },
                ),
                const SizedBox(width: 12),
                _PlatformTabButton(
                  label: '📘 Facebook Live',
                  active: _selectedPlatformTab == 1,
                  onTap: () {
                    if (_selectedPlatformTab == 1) return;
                    setState(() => _selectedPlatformTab = 1);
                    _loadPlatformData();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _loadPlatformData(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _SectionLabel(label: 'Phiên livestream hiện tại'),
            _loadingActive
                ? const _Card(
                    child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CupertinoActivityIndicator())))
                : _activeSession == null
                    ? _NoActiveLiveCard(platform: _currentPlatformStr)
                    : _ActiveLiveCard(
                        session: _activeSession!,
                        comments: _realtimeComments,
                        onLuckyWheelTap: () {
                          Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => LuckyWheelScreen(
                                session:
                                    _buildLiveSessionModel(_activeSession!),
                              ),
                            ),
                          );
                        },
                        onCommentTap: (comment) {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => CreateOrderSheet(
                              comment: comment,
                              session: _buildLiveSessionModel(_activeSession!),
                            ),
                          );
                        },
                      ),
            const SizedBox(height: 20),
            const _SectionLabel(label: 'Lịch sử phiên live trước đó'),
            _loadingHistory
                ? const Center(
                    child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CupertinoActivityIndicator()))
                : _historySessions.isEmpty
                    ? Center(
                        child: Text('Chưa có lịch sử live trên nền tảng này',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade500)))
                    : Container(
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14)),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _historySessions.length,
                          separatorBuilder: (_, __) => const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child:
                                  Divider(height: 1, color: Color(0xFFE5E5EA))),
                          itemBuilder: (ctx, i) {
                            final item = _historySessions[i];
                            final title =
                                item['title'] as String? ?? 'Phiên Live cũ';
                            final createdAt =
                                DateTime.parse(item['created_at'] as String)
                                    .toLocal();

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    shape: BoxShape.circle),
                                child: Icon(CupertinoIcons.time,
                                    size: 18, color: Colors.grey.shade600),
                              ),
                              title: Text(title,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                'Ngày live: ${createdAt.day}/${createdAt.month}/${createdAt.year} lúc ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: const Icon(CupertinoIcons.chevron_right,
                                  size: 14, color: Colors.grey),
                              onTap: () {
                                // 🚀 LOGIC ĐỒNG BỘ XEM LẠI LỊCH SỬ COMMENT ĐỂ CHỐT BÙ/SỬA ĐƠN
                                Navigator.push(
                                  context,
                                  CupertinoPageRoute(
                                    builder: (_) => LiveCommentsScreen(
                                      session: _buildLiveSessionModel(item),
                                    ),
                                  ),
                                ).then((_) => _fetchHistorySessions());
                              },
                            );
                          },
                        ),
                      ),
          ],
        ),
      ),
    );
  }
}

// Giữ các Widget thành phần phụ (_PlatformTabButton, _ActiveLiveCard, _NoActiveLiveCard, _Card, _SectionLabel) giống như phiên bản hiện tại của bạn...
class _PlatformTabButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PlatformTabButton(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF007AFF) : const Color(0xFFE5E5EA),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : Colors.black87),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveLiveCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final List<LiveComment> comments;
  final VoidCallback onLuckyWheelTap;
  final Function(LiveComment) onCommentTap;

  const _ActiveLiveCard({
    required this.session,
    required this.comments,
    required this.onLuckyWheelTap,
    required this.onCommentTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Row(
                    children: [
                      Icon(CupertinoIcons.radiowaves_right,
                          color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text('DANG LIVE',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    session['title'] as String? ?? 'Phiên kết nối tự động',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: onLuckyWheelTap,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFF9F0A).withValues(alpha: 0.15),
                        shape: BoxShape.circle),
                    child: const Icon(CupertinoIcons.gift_fill,
                        color: Color(0xFFFF9F0A), size: 22),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(height: 1, color: Color(0xFFE5E5EA))),
          Container(
            height: 260,
            color: const Color(0xFFF2F2F7).withValues(alpha: 0.4),
            child: comments.isEmpty
                ? Center(
                    child: Text('Đang đợi luồng bình luận đổ về...',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic)))
                : ListView.builder(
                    itemCount: comments.length,
                    padding: const EdgeInsets.all(12),
                    itemBuilder: (ctx, i) {
                      final cm = comments[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          dense: true,
                          title: Text(cm.commenterName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF007AFF),
                                  fontSize: 13)),
                          subtitle: Text(cm.commentText,
                              style: const TextStyle(
                                  color: Color(0xFF1C1C1E), fontSize: 13)),
                          trailing: const Text('Chốt cây 📝',
                              style: TextStyle(
                                  color: Color(0xFF34C759),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11)),
                          onTap: () => onCommentTap(cm),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _NoActiveLiveCard extends StatelessWidget {
  final String platform;
  const _NoActiveLiveCard({required this.platform});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Icon(CupertinoIcons.arrow_clockwise,
              size: 36, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'Nhà vườn chưa lên sóng Live trên ${platform.toUpperCase()}',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(
            'Hệ thống tự quét luồng 24/7. Khi bạn bật Live ở điện thoại, mục này sẽ tự động sáng lên.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: child);
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6, top: 8),
      child: Text(label.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
              letterSpacing: 0.5)));
}

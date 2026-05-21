import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/livestream_models.dart';

// ============================================================
// LIVESTREAM REPOSITORY
// Tất cả queries Supabase liên quan đến livestream
// ============================================================

class LivestreamRepository {
  final _db = Supabase.instance.client;

  // ── Lấy danh sách phiên live ─────────────────────────────
  // Lấy 30 phiên gần nhất, ưu tiên phiên đang live lên đầu
  Future<List<LiveSession>> getSessions() async {
    final res = await _db
        .from('livestream_sessions')
        .select()
        .filter('deleted_at', 'is',
            null) // <--- Sửa thành .filter(...) ở đây để check NULL an toàn
        .order('created_at', ascending: false)
        .limit(30);

    return (res as List).map((e) => LiveSession.fromJson(e)).toList();
  }

  // ── Tạo phiên live mới ───────────────────────────────────
  Future<LiveSession> createSession({
    required String platform,
    String? title,
  }) async {
    final now = DateTime.now();
    final label = platform == 'tiktok' ? 'TikTok' : 'Facebook';
    final defaultTitle =
        '$label Live – ${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';

    final res = await _db
        .from('livestream_sessions')
        .insert({
          'title': title ?? defaultTitle,
          'platform': platform,
          'status': 'live',
        })
        .select()
        .single();

    return LiveSession.fromJson(res);
  }

  // ── Kết thúc phiên live ──────────────────────────────────
  Future<void> endSession(String sessionId) async {
    await _db.from('livestream_sessions').update({
      'status': 'ended',
      'ended_at': DateTime.now().toIso8601String(),
    }).eq('id', sessionId);
  }

  // ── Lấy bình luận của 1 phiên (lần đầu load) ────────────
  Future<List<LiveComment>> getComments(String sessionId,
      {int limit = 100}) async {
    final res = await _db
        .from('livestream_comments')
        .select()
        .eq('session_id', sessionId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (res as List).map((e) => LiveComment.fromJson(e)).toList();
  }

  // ── Realtime stream bình luận mới ───────────────────────
  // Trả về Stream để UI lắng nghe liên tục
  RealtimeChannel subscribeComments(
    String sessionId,
    void Function(LiveComment comment) onNewComment,
  ) {
    return _db
        .channel('comments:$sessionId')
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
            try {
              final comment = LiveComment.fromJson(payload.newRecord);
              onNewComment(comment);
            } catch (_) {}
          },
        )
        .subscribe();
  }
}

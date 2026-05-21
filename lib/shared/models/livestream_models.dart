// ============================================================
// MODELS – Nhà Vườn Livestream
// ============================================================

class LiveSession {
  final String id;
  final String title;
  final String platform; // 'tiktok' | 'facebook'
  final String status; // 'live' | 'ended'
  final DateTime createdAt;
  final DateTime? endedAt;
  final int? totalOrders;
  final double? totalRevenue;

  const LiveSession({
    required this.id,
    required this.title,
    required this.platform,
    required this.status,
    required this.createdAt,
    this.endedAt,
    this.totalOrders,
    this.totalRevenue,
  });

  factory LiveSession.fromJson(Map<String, dynamic> json) => LiveSession(
        id: json['id'] as String,
        title: json['title'] as String,
        platform: json['platform'] as String? ?? 'tiktok',
        status: json['status'] as String? ?? 'ended',
        createdAt: DateTime.parse(json['created_at'] as String),
        endedAt: json['ended_at'] != null
            ? DateTime.parse(json['ended_at'] as String)
            : null,
        totalOrders: json['total_orders'] as int?,
        totalRevenue: (json['total_revenue'] as num?)?.toDouble(),
      );

  bool get isLive => status == 'live';

  String get platformLabel => platform == 'tiktok' ? 'TikTok' : 'Facebook';

  String get platformEmoji => platform == 'tiktok' ? '🎵' : '📘';
}

// ────────────────────────────────────────────────────────────

class LiveComment {
  final String id;
  final String sessionId;
  final String commenterName;
  final String commentText;
  final String? username;
  final String? platform;
  final String? customerId;
  final DateTime createdAt;

  const LiveComment({
    required this.id,
    required this.sessionId,
    required this.commenterName,
    required this.commentText,
    this.username,
    this.platform,
    this.customerId,
    required this.createdAt,
  });

  factory LiveComment.fromJson(Map<String, dynamic> json) => LiveComment(
        id: json['id'] as String,
        sessionId: json['session_id'] as String? ?? '',
        commenterName: json['commenter_name'] as String? ?? 'Ẩn danh',
        commentText: json['comment_text'] as String,
        username: json['username'] as String?,
        platform: json['platform'] as String?,
        customerId: json['customer_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  /// Avatar chữ cái đầu
  String get avatarLetter =>
      commenterName.isNotEmpty ? commenterName[0].toUpperCase() : '?';
}

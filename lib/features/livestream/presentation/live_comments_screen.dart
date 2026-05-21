import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/livestream_repository.dart';
import '../../../../shared/models/livestream_models.dart';
import 'create_order_sheet.dart';

class LiveCommentsScreen extends StatefulWidget {
  final LiveSession session;
  const LiveCommentsScreen({super.key, required this.session});

  @override
  State<LiveCommentsScreen> createState() => _LiveCommentsScreenState();
}

class _LiveCommentsScreenState extends State<LiveCommentsScreen> {
  final _repo = LivestreamRepository();
  final _scrollController = ScrollController();

  List<LiveComment> _comments = [];
  bool _loading = true;
  bool _autoScroll = true;
  RealtimeChannel? _channel;

  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadComments();
    // Chỉ kết nối Websocket lắng nghe nếu phiên đang phát TRỰC TIẾP
    if (widget.session.isLive) _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() => _loading = true);
    try {
      final comments = await _repo.getComments(widget.session.id);
      setState(() {
        _comments = comments.reversed.toList();
      });
      _scrollToBottom();
    } catch (e) {
      _showError('Lỗi tải bình luận lịch sử: $e');
    } finally {
      setState(() => _loading = false); // Đã fix lỗi Alexander_loading
    }
  }

  void _subscribeRealtime() {
    _channel = _repo.subscribeComments(
      widget.session.id,
      (newComment) {
        if (mounted) {
          setState(() => _comments.add(newComment));
          if (_autoScroll) _scrollToBottom();
        }
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _endSession() async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Kết thúc phiên Live?'),
        content: const Text(
            'Phiên sẽ chuyển sang lịch sử. Bạn vẫn có thể xem và chỉnh đơn hàng sau.'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kết thúc'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Tiếp tục Live'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await _repo.endSession(widget.session.id);
    if (mounted) Navigator.pop(context);
  }

  void _onCommentTap(LiveComment comment) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateOrderSheet(
        comment: comment,
        session: widget.session,
      ),
    );
  }

  List<LiveComment> get _filteredComments {
    if (_filter == 'phone') {
      return _comments.where((c) {
        return RegExp(r'0[35789]\d{8}').hasMatch(c.commentText);
      }).toList();
    }
    return _comments;
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFFFF3B30),
          behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLive = widget.session.isLive;
    final filtered = _filteredComments;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(CupertinoIcons.chevron_left, size: 20),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isLive) ...[
                  _LiveDot(),
                  const SizedBox(width: 6),
                ] else ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(4)),
                    child: const Text('LỊCH SỬ',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    widget.session.title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Text(
              '${widget.session.platformEmoji} ${widget.session.platformLabel} · ${filtered.length} bình luận',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          if (isLive) ...[
            IconButton(
              onPressed: () => setState(() => _autoScroll = !_autoScroll),
              icon: Icon(
                _autoScroll
                    ? CupertinoIcons.arrow_down_to_line
                    : CupertinoIcons.pause_fill,
                size: 18,
                color: _autoScroll
                    ? const Color(0xFF007AFF)
                    : Colors.grey.shade400,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _endSession,
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFF3B30)),
                child: const Text('Kết thúc',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              ),
            ),
          ]
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: _FilterBar(
            selected: _filter,
            onChanged: (v) => setState(() => _filter = v),
            totalCount: _comments.length,
            phoneCount: _comments
                .where((c) => RegExp(r'0[35789]\d{8}').hasMatch(c.commentText))
                .length,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : filtered.isEmpty
              ? _buildEmpty()
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is UserScrollNotification && _autoScroll) {
                      final atBottom = _scrollController.position.pixels >=
                          _scrollController.position.maxScrollExtent - 50;
                      if (!atBottom) setState(() => _autoScroll = false);
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) => _CommentBubble(
                      comment: filtered[i],
                      onTap: () => _onCommentTap(filtered[i]),
                    ),
                  ),
                ),
      floatingActionButton: !_autoScroll && isLive
          ? FloatingActionButton.small(
              onPressed: () {
                setState(() => _autoScroll = true);
                _scrollToBottom();
              },
              backgroundColor: const Color(0xFF007AFF),
              child: const Icon(CupertinoIcons.arrow_down, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center, // Đã fix lỗi Maincenter
        children: [
          const Text('💬', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            widget.session.isLive
                ? 'Đang chờ bình luận...'
                : 'Không có bình luận nào',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  final int totalCount;
  final int phoneCount;

  const _FilterBar(
      {required this.selected,
      required this.onChanged,
      required this.totalCount,
      required this.phoneCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: [
          _FilterChip(
              label: 'Tất cả ($totalCount)',
              selected: selected == 'all',
              onTap: () => onChanged('all')),
          const SizedBox(width: 8),
          _FilterChip(
              label: '📞 Có SĐT ($phoneCount)',
              selected: selected == 'phone',
              onTap: () => onChanged('phone'),
              activeColor: const Color(0xFF34C759)),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color activeColor;

  const _FilterChip(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.activeColor = const Color(0xFF007AFF)});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
            color: selected ? activeColor : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey.shade600)),
      ),
    );
  }
}

class _CommentBubble extends StatelessWidget {
  final LiveComment comment;
  final VoidCallback onTap;

  const _CommentBubble({required this.comment, required this.onTap});

  bool get _hasPhone => RegExp(r'0[35789]\d{8}').hasMatch(comment.commentText);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: const Color(0xFF007AFF).withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(letter: comment.avatarLetter, hasPhone: _hasPhone),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(comment.commenterName,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2)),
                          const SizedBox(width: 6),
                          Text(
                              '${comment.createdAt.hour}:${comment.createdAt.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade400)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      _hasPhone
                          ? _HighlightedText(text: comment.commentText)
                          : Text(comment.commentText,
                              style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  letterSpacing: -0.1)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _hasPhone
                          ? const Color(0xFF34C759)
                          : const Color(0xFF007AFF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Tạo đơn',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String letter;
  final bool hasPhone;
  const _Avatar({required this.letter, required this.hasPhone});

  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFF5E5CE6),
      const Color(0xFF30B0C7),
      const Color(0xFFFF9F0A),
      const Color(0xFF34C759),
      const Color(0xFFFF375F)
    ];
    final color = colors[letter.codeUnitAt(0) % colors.length];
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: hasPhone
              ? Border.all(color: const Color(0xFF34C759), width: 2)
              : null),
      child: Center(
          child: Text(letter,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: color))),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  final String text;
  const _HighlightedText({required this.text});

  @override
  Widget build(BuildContext context) {
    final phoneRegex = RegExp(r'(0[35789]\d{8})');
    final spans = <TextSpan>[];
    int last = 0;

    for (final match in phoneRegex.allMatches(text)) {
      if (match.start > last)
        spans.add(TextSpan(text: text.substring(last, match.start)));
      spans.add(TextSpan(
          text: match.group(0),
          style: const TextStyle(
              color: Color(0xFF007AFF),
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline)));
      last = match.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));

    return RichText(
        text: TextSpan(
            style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF1C1C1E),
                height: 1.4,
                letterSpacing: -0.1),
            children: spans));
  }
}

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
      opacity: _anim,
      child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
              color: Color(0xFFFF3B30), shape: BoxShape.circle)));
}

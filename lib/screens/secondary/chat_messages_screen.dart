import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/design/app_colors.dart';
import '../../core/api/api_endpoints.dart';
import '../../services/chat_service.dart';
import '../../services/chat_websocket_service.dart';
import '../../services/profile_service.dart';

/// Chat messages screen – WhatsApp-style bubbles, app colors.
class ChatMessagesScreen extends StatefulWidget {
  final String conversationId;
  final Map<String, dynamic>? otherUser;
  final Map<String, dynamic>? conversation;

  const ChatMessagesScreen({
    super.key,
    required this.conversationId,
    this.otherUser,
    this.conversation,
  });

  @override
  State<ChatMessagesScreen> createState() => _ChatMessagesScreenState();
}

class _ChatMessagesScreenState extends State<ChatMessagesScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _loading = true;
  bool _sending = false;
  List<Map<String, dynamic>> _messages = [];
  String? _currentUserId;
  File? _pendingImage;
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadUserId();
    _loadMessages();
    _connectWebSocket();
    _startPolling();
  }

  void _connectWebSocket() {
    ChatWebSocketService.instance.connect(widget.conversationId);
    _wsSubscription = ChatWebSocketService.instance.onMessage.listen(
      (msg) {
        if (!mounted) return;
        final id = msg['id']?.toString();
        if (id == null || id.isEmpty) return;
        final exists = _messages.any((m) => m['id']?.toString() == id);
        if (exists) return;
        setState(() => _messages.add(msg));
        _scrollToBottom();
      },
      onError: (e) {
        // Connection/socket errors – avoid unhandled exceptions
      },
      cancelOnError: false,
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _wsSubscription?.cancel();
    ChatWebSocketService.instance.disconnect();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Background refresh every 5 seconds – merges new messages without user notice.
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      _refreshMessagesInBackground();
    });
  }

  Future<void> _refreshMessagesInBackground() async {
    if (_loading) return; // Skip during initial load
    try {
      final res = await ChatService.instance.getMessages(
        widget.conversationId,
        page: 1,
        limit: 100,
      );
      final raw = res['messages'] ?? res['data'] ?? res['items'] ?? [];
      final list = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      final existingIds =
          _messages.map((m) => m['id']?.toString()).whereType<String>().toSet();
      final newMessages = list.where((m) {
        final id = m['id']?.toString();
        return id != null && id.isNotEmpty && !existingIds.contains(id);
      }).toList();
      if (newMessages.isEmpty) return;
      // Merge: append new messages and sort by createdAt to preserve order
      final merged = [..._messages];
      for (final m in newMessages) {
        merged.add(m);
        existingIds.add(m['id']?.toString() ?? '');
      }
      merged.sort((a, b) {
        final aAt = a['createdAt'] ?? a['created_at'] ?? '';
        final bAt = b['createdAt'] ?? b['created_at'] ?? '';
        return (aAt.toString()).compareTo(bAt.toString());
      });
      if (mounted) {
        setState(() => _messages = merged);
        _markIncomingMessagesAsRead(newMessages);
      }
    } catch (_) {
      // Silent – user doesn't need to know about background refresh failures
    }
  }

  Future<void> _loadUserId() async {
    try {
      final profile = await ProfileService.instance.getProfile();
      final id = profile['id']?.toString() ??
          (profile['user'] as Map?)?['id']?.toString();
      if (mounted) {
        setState(() => _currentUserId = id);
      }
    } catch (_) {}
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    try {
      final res = await ChatService.instance.getMessages(widget.conversationId);
      final list = res['messages'] ?? res['data'] ?? res['items'] ?? [];
      final msgs = list is List
          ? list
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _messages = msgs;
          _loading = false;
        });
        _scrollToBottom();
        _markIncomingMessagesAsRead(msgs);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// PATCH /api/chat/messages/:messageId/read – mark messages from other user as read.
  void _markIncomingMessagesAsRead(List<Map<String, dynamic>> messages) {
    final myId = _currentUserId;
    if (myId == null || myId.isEmpty) return;
    final toMark = messages
        .where((m) => m['senderId']?.toString() != myId)
        .map((m) => m['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
    if (toMark.isEmpty) return;
    // Limit to last 30 to avoid too many requests
    final ids =
        toMark.length > 30 ? toMark.sublist(toMark.length - 30) : toMark;
    for (final id in ids) {
      ChatService.instance.markMessageRead(id).catchError((_) {});
    }
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

  Future<void> _pickChatImage(ImageSource source) async {
    try {
      String? path;
      if (source == ImageSource.camera) {
        final XFile? image = await _imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
          maxWidth: 2048,
          maxHeight: 2048,
        );
        path = image?.path;
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
        path = result?.files.singleOrNull?.path;
      }
      final validPath = path?.trim();
      if (validPath != null && validPath.isNotEmpty && mounted) {
        setState(() => _pendingImage = File(validPath));
      }
    } catch (e) {
      if (kDebugMode) print('❌ Chat image pick: $e');
    }
  }

  void _showImageSourceSheet(bool isAr) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: Text(isAr ? 'الكاميرا' : 'Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickChatImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(isAr ? 'معرض الصور' : 'Photo library'),
              onTap: () {
                Navigator.pop(ctx);
                _pickChatImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  String? _messageImageUrl(Map<String, dynamic> msg) {
    for (final key in [
      'imageUrl',
      'imageURL',
      'image',
      'attachmentUrl',
      'mediaUrl',
      'imagePath',
    ]) {
      final v = msg[key];
      if (v != null && v.toString().isNotEmpty) {
        return ApiEndpoints.getImageUrl(v.toString());
      }
    }
    return null;
  }

  Future<void> _sendMessage() async {
    final body = _controller.text.trim();
    final imageFile = _pendingImage;
    if (body.isEmpty && imageFile == null) return;
    if (_sending) return;

    final tempId = 'temp-${DateTime.now().millisecondsSinceEpoch}';
    final localPath = imageFile?.path;
    _controller.clear();
    setState(() {
      _pendingImage = null;
      _sending = true;
      _messages.add({
        'id': tempId,
        'body': body,
        if (localPath != null) 'localImagePath': localPath,
        'senderId': _currentUserId,
        'createdAt': DateTime.now().toIso8601String(),
        'isSent': true,
      });
    });
    _scrollToBottom();

    try {
      final sent = await ChatService.instance.sendMessage(
        widget.conversationId,
        body: body.isEmpty ? null : body,
        imageFile: imageFile,
      );
      if (mounted) {
        final idx = _messages.indexWhere((m) => m['id'] == tempId);
        if (idx >= 0) {
          setState(() {
            _messages[idx] = {
              ..._messages[idx],
              ...sent,
              'id': sent['id'] ?? tempId,
            };
            _messages[idx].remove('localImagePath');
          });
        }
      }
    } catch (e) {
      if (mounted) {
        final idx = _messages.indexWhere((m) => m['id'] == tempId);
        if (idx >= 0) {
          setState(() => _messages[idx]['failed'] = true);
        }
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final other = widget.otherUser ?? {};
    final name =
        other['name'] ?? other['userName'] ?? (isAr ? 'مستخدم' : 'User');
    final avatar = other['avatar'];

    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white.withOpacity(0.3),
              backgroundImage: avatar != null && avatar.toString().isNotEmpty
                  ? NetworkImage(ApiEndpoints.getImageUrl(avatar.toString()))
                  : null,
              child: avatar == null || avatar.toString().isEmpty
                  ? Text(
                      (name.toString().isNotEmpty ? name[0] : '?')
                          .toUpperCase(),
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name.toString(),
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.purple,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          isAr ? 'لا توجد رسائل بعد' : 'No messages yet',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) =>
                            _buildMessageBubble(_messages[i], isAr),
                      ),
          ),
          _buildInputBar(isAr),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isAr) {
    final body = msg['body']?.toString() ?? '';
    final senderId =
        msg['senderId']?.toString() ?? msg['sender_id']?.toString();
    final isMe = senderId == _currentUserId;
    final createdAt = msg['createdAt'] ?? msg['created_at'];
    final failed = msg['failed'] == true;
    final remoteUrl = _messageImageUrl(msg);
    final localPath = msg['localImagePath']?.toString();
    final hasImage = (remoteUrl != null && remoteUrl.isNotEmpty) ||
        (localPath != null && localPath.isNotEmpty);

    return Align(
      alignment: isMe
          ? (isAr ? Alignment.centerRight : Alignment.centerRight)
          : (isAr ? Alignment.centerLeft : Alignment.centerLeft),
      child: Container(
        margin: EdgeInsets.only(
          bottom: 8,
          left: isMe ? 64 : 0,
          right: isMe ? 0 : 64,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AppColors.purple : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (hasImage) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 220, maxHeight: 280),
                  child: localPath != null && localPath.isNotEmpty
                      ? Image.file(
                          File(localPath),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image),
                        )
                      : remoteUrl != null && remoteUrl.isNotEmpty
                          ? Image.network(
                              remoteUrl,
                              fit: BoxFit.cover,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return SizedBox(
                                  height: 120,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: isMe
                                          ? Colors.white70
                                          : AppColors.purple,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.broken_image_rounded,
                                color: isMe
                                    ? Colors.white70
                                    : AppColors.mutedForeground,
                              ),
                            )
                          : const SizedBox.shrink(),
                ),
              ),
              if (body.isNotEmpty) const SizedBox(height: 8),
            ],
            if (body.isNotEmpty)
              Text(
                body,
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  color: isMe ? Colors.white : AppColors.foreground,
                  height: 1.4,
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (createdAt != null)
                  Text(
                    _formatTime(createdAt.toString()),
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      color: isMe
                          ? Colors.white.withOpacity(0.8)
                          : AppColors.mutedForeground,
                    ),
                  ),
                if (isMe && failed) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.error_outline_rounded,
                    size: 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(bool isAr) {
    final canSend = !_sending &&
        (_pendingImage != null || _controller.text.trim().isNotEmpty);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.white,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_pendingImage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _pendingImage!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _sending
                          ? null
                          : () => setState(() => _pendingImage = null),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: isAr ? 'إزالة' : 'Remove',
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  onPressed:
                      _sending ? null : () => _showImageSourceSheet(isAr),
                  icon: const Icon(Icons.image_rounded),
                  color: AppColors.purple,
                  tooltip: isAr ? 'إرفاق صورة' : 'Attach image',
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: isAr ? 'اكتب رسالة...' : 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: AppColors.beige,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    style: GoogleFonts.cairo(fontSize: 15),
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) {
                      if (canSend) _sendMessage();
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Material(
                  color: canSend
                      ? AppColors.purple
                      : AppColors.purple.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    onTap: canSend ? _sendMessage : null,
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _sending
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.tryParse(iso);
      if (dt == null) return '';
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}

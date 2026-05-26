// lib/widgets/chat_images_scope.dart
import 'dart:convert';
import 'package:flutter/widgets.dart';
import '../models/chat_message.dart';
import 'album_message_widget.dart';

/// Provides a flat list of ALL image items from the entire chat to descendant
/// widgets. Both [ImageMessageWidget] and [AlbumMessageWidget] read this to
/// show the full-chat filmstrip instead of being limited to a single album.
class ChatImagesScope extends InheritedWidget {
  final List<AlbumItem> allImages;

  const ChatImagesScope({
    super.key,
    required this.allImages,
    required super.child,
  });

  static ChatImagesScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ChatImagesScope>();
  }

  @override
  bool updateShouldNotify(ChatImagesScope old) => allImages != old.allImages;

  static List<AlbumItem> computeFromChatMessages(List<ChatMessage> messages) {
    final result = <AlbumItem>[];
    for (final msg in messages) {
      _extractImages(msg.content, result);
    }
    return result;
  }

  static List<AlbumItem> computeFromGroupMessages(
      List<Map<String, dynamic>> messages) {
    final result = <AlbumItem>[];
    for (final msg in messages) {
      _extractImages(msg['content']?.toString() ?? '', result);
    }
    return result;
  }

  static void _extractImages(String content, List<AlbumItem> out) {
    if (content.startsWith('IMAGEv1:')) {
      try {
        final data =
            jsonDecode(content.substring('IMAGEv1:'.length)) as Map<String, dynamic>;
        final filename =
            data['url'] as String? ?? data['filename'] as String? ?? '';
        if (filename.isEmpty) return;
        out.add(AlbumItem(
          filename: filename,
          orig: data['orig'] as String? ?? '',
          owner: data['owner'] as String?,
          mediaKeyB64: data['key'] as String?,
        ));
      } catch (_) {}
    } else if (content.startsWith('ALBUMv1:')) {
      try {
        final list =
            jsonDecode(content.substring('ALBUMv1:'.length)) as List<dynamic>;
        for (final item in list.whereType<Map<String, dynamic>>()) {
          final albumItem = AlbumItem.fromJson(item);
          if (albumItem.filename.isNotEmpty) out.add(albumItem);
        }
      } catch (_) {}
    }
  }
}

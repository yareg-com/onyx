// lib/screens/favorites_tab.dart
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ONYX/globals.dart';
import 'package:ONYX/managers/settings_manager.dart';
import 'package:ONYX/models/chat_message.dart';
import 'package:ONYX/models/fav_folder.dart';
import 'package:ONYX/models/favorite_chat.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../widgets/adaptive_glass_card.dart';
import '../widgets/avatar_crop_screen.dart';
import 'fav_sync_receive_screen.dart';
import 'fav_sync_send_screen.dart';
import '../managers/lock_manager.dart';
import '../dialogs/pin_lock_dialog.dart';

String _formatTime(DateTime t) {
  final now = DateTime.now();
  if (now.difference(t).inDays == 0) {
    return '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
  }
  return '${t.day}.${t.month}';
}

String _getFileTypeLabel(String filename) {
  final ext = filename.toLowerCase();
  if (ext.endsWith('.mp3') || ext.endsWith('.wav') || ext.endsWith('.m4a') ||
      ext.endsWith('.aac') || ext.endsWith('.flac') || ext.endsWith('.wma')) {
    return 'Music';
  }
  if (ext.endsWith('.mp4') || ext.endsWith('.mkv') || ext.endsWith('.mov') ||
      ext.endsWith('.avi') || ext.endsWith('.wmv') || ext.endsWith('.flv')) {
    return 'Video';
  }
  if (ext.endsWith('.jpg') || ext.endsWith('.jpeg') ||
      ext.endsWith('.png') || ext.endsWith('.gif') || ext.endsWith('.webp')) {
    return 'Image';
  }
  if (ext.endsWith('.pdf')) return 'Document';
  if (ext.endsWith('.doc') || ext.endsWith('.docx')) return 'Document';
  if (ext.endsWith('.xls') || ext.endsWith('.xlsx')) return 'Spreadsheet';
  if (ext.endsWith('.ppt') || ext.endsWith('.pptx')) return 'Presentation';
  if (ext.endsWith('.zip') || ext.endsWith('.rar') || ext.endsWith('.7z')) {
    return 'Archive';
  }
  return 'File';
}

bool _isPurplePreview(String preview) {
  const purpleLabels = {
    'Voice message', 'Music', 'Image', 'Video', 'Video file',
    'Document', 'Spreadsheet', 'Presentation', 'Archive', 'Artifact', 'File'
  };
  if (preview.startsWith('[Message not decrypted]')) return true;
  if (preview == 'Album' || preview.startsWith('Album ·')) return true;
  return purpleLabels.contains(preview);
}

String _getPreviewText(String rawContent) {
  if (rawContent.startsWith('VOICEv1:')) return 'Voice message';
  if (rawContent.startsWith('AUDIOv1:')) return 'Music';
  if (rawContent.startsWith('IMAGEv1:')) return 'Image';
  if (rawContent.startsWith('VIDEOv1:') ||
      rawContent.toUpperCase().startsWith('VIDEOV1:')) return 'Video file';
  if (rawContent.startsWith('MEDIA_PROXYv1:') ||
      rawContent.startsWith('MEDIA_PROXY:')) {
    try {
      final jsonPart = rawContent.substring(rawContent.indexOf(':') + 1);
      final data = jsonDecode(jsonPart) as Map<String, dynamic>;
      final type = (data['type'] as String?)?.toLowerCase();
      final orig =
          (data['orig'] ?? data['filename'] ?? data['name'] ?? '') as String;
      if (type == 'voice') return 'Voice message';
      if (type == 'audio') return 'Music';
      if (type == 'video') return 'Video';
      if (type == 'image') return 'Image';
      if (orig.isNotEmpty) return _getFileTypeLabel(orig);
      return 'File';
    } catch (_) {
      return 'File';
    }
  }
  if (rawContent.startsWith('FILEv1:') ||
      rawContent.startsWith('DOCUMENTv1:') ||
      rawContent.startsWith('ARCHIVEv1:') ||
      rawContent.startsWith('DATAv1:')) {
    try {
      final jsonPart = rawContent.substring(rawContent.indexOf(':') + 1);
      final meta = jsonDecode(jsonPart) as Map<String, dynamic>;
      final filename =
          (meta['filename'] ?? meta['orig'] ?? meta['name'] ?? 'File') as String;
      return _getFileTypeLabel(filename);
    } catch (_) {
      return 'File';
    }
  }
  if (rawContent.startsWith('FILE:')) {
    return _getFileTypeLabel(rawContent.substring(5));
  }
  if (rawContent.startsWith('ALBUMv1:')) {
    try {
      final list = jsonDecode(rawContent.substring('ALBUMv1:'.length)) as List;
      return 'Album · ${list.length} photos';
    } catch (_) {
      return 'Album';
    }
  }
  if (rawContent.startsWith('[cannot-decrypt]')) {
    return '[Message not decrypted]';
  }
  return rawContent;
}

String _getFavPreview(String favId, Map<String, List<ChatMessage>> allChats) {
  final msgs = allChats['fav:$favId'] ?? [];
  if (msgs.isEmpty) return '';
  return _getPreviewText(msgs.last.content);
}

DateTime _getFavLastTs(String favId, Map<String, List<ChatMessage>> allChats) {
  final msgs = allChats['fav:$favId'] ?? [];
  if (msgs.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
  return msgs.last.time;
}


class FavoritesTab extends StatefulWidget {
  final List<FavoriteChat> favorites;
  final void Function(String id) onOpen;
  final void Function(FavoriteChat chat) onAdd;
  final void Function(String id) onDelete;

  const FavoritesTab({
    super.key,
    required this.favorites,
    required this.onOpen,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  State<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<FavoritesTab>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  late final AnimationController _listAnimController;
  bool _editMode = false;
  String? _openFolderId;

  late double _staggerStep;

  @override
  void initState() {
    super.initState();
    final dur = Platform.isWindows
        ? const Duration(milliseconds: 120)
        : const Duration(milliseconds: 350);
    _staggerStep = Platform.isWindows ? 0.02 : 0.05;
    _listAnimController = AnimationController(duration: dur, vsync: this);
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _listAnimController.forward();
    });
  }

  @override
  void dispose() {
    _listAnimController.dispose();
    super.dispose();
  }

  // ── Action sheets ──────────────────────────────────────────────────────────

  void _showAddSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: SettingsManager.getElementColor(
                cs.surfaceContainerHighest,
                SettingsManager.elementBrightness.value),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: cs.primaryContainer,
                  child: Icon(Icons.chat_bubble_outline_rounded,
                      size: 18, color: cs.primary),
                ),
                title: Text(l.newChat),
                subtitle: Text(l.newChatSubtitle),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showDialog<void>(
                    context: context,
                    builder: (_) => _NewChatDialog(onAdd: widget.onAdd),
                  );
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: cs.secondaryContainer,
                  child: Icon(Icons.folder_outlined,
                      size: 18, color: cs.secondary),
                ),
                title: Text(l.newFolder),
                subtitle: Text(l.newFolderSubtitle),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showDialog<void>(
                    context: context,
                    builder: (_) => const _NewFolderDialog(),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showDesktopContextMenu(
      BuildContext context, Offset pos, FavoriteChat fav, List<FavFolder> folders) {
    final cs = Theme.of(context).colorScheme;
    final currentFolder =
        folders.where((f) => f.chatIds.contains(fav.id)).firstOrNull;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        if (currentFolder != null)
          PopupMenuItem<String>(
            value: 'remove_folder',
            child: Row(children: [
              Icon(Icons.folder_off_outlined, size: 18, color: cs.onSurface),
              const SizedBox(width: 10),
              Text('Remove from "${currentFolder.name}"'),
            ]),
          ),
        if (folders.isNotEmpty)
          PopupMenuItem<String>(
            value: 'move',
            child: Row(children: [
              Icon(Icons.drive_file_move_outline, size: 18, color: cs.onSurface),
              const SizedBox(width: 10),
              const Text('Move to folder'),
            ]),
          ),
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_outlined, size: 18, color: cs.onSurface),
            const SizedBox(width: 10),
            const Text('Edit'),
          ]),
        ),
        PopupMenuItem<String>(
          value: LockManager.isLocked('fav_${fav.id}') ? 'unlock' : 'lock',
          child: Row(children: [
            Icon(
              LockManager.isLocked('fav_${fav.id}') ? Icons.lock_open_rounded : Icons.lock_rounded,
              size: 18, color: cs.onSurface,
            ),
            const SizedBox(width: 10),
            Text(LockManager.isLocked('fav_${fav.id}') ? 'Unlock' : 'Lock'),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline, size: 18, color: cs.error),
            const SizedBox(width: 10),
            Text('Delete', style: TextStyle(color: cs.error)),
          ]),
        ),
      ],
    ).then((value) async {
      if (!context.mounted) return;
      if (value == 'remove_folder') {
        rootScreenKey.currentState?.moveChatOutOfFolder(fav.id);
      } else if (value == 'move') {
        _showFolderPicker(context, fav, folders);
      } else if (value == 'edit') {
        showDialog<void>(context: context, builder: (_) => _EditChatDialog(fav: fav));
      } else if (value == 'lock') {
        final lockId = 'fav_${fav.id}';
        final set = await showPinDialog(context, PinDialogMode.set, lockId);
        if (!set) return;
        await LockManager.lock(lockId);
      } else if (value == 'unlock') {
        final lockId = 'fav_${fav.id}';
        final ok = await showPinDialog(context, PinDialogMode.verify, lockId);
        if (ok) await LockManager.removeLock(lockId);
      } else if (value == 'delete') {
        _confirmDelete(context, fav);
      }
    });
  }

  void _showDesktopInlineContextMenu(
      BuildContext context, Offset pos, FavoriteChat fav, ColorScheme cs) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem<String>(
          value: 'remove_folder',
          child: Row(children: [
            Icon(Icons.folder_off_outlined, size: 18, color: cs.onSurface),
            const SizedBox(width: 10),
            const Text('Remove from folder'),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_outlined, size: 18, color: cs.onSurface),
            const SizedBox(width: 10),
            const Text('Edit'),
          ]),
        ),
        PopupMenuItem<String>(
          value: LockManager.isLocked('fav_${fav.id}') ? 'unlock' : 'lock',
          child: Row(children: [
            Icon(
              LockManager.isLocked('fav_${fav.id}') ? Icons.lock_open_rounded : Icons.lock_rounded,
              size: 18, color: cs.onSurface,
            ),
            const SizedBox(width: 10),
            Text(LockManager.isLocked('fav_${fav.id}') ? 'Unlock' : 'Lock'),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline, size: 18, color: cs.error),
            const SizedBox(width: 10),
            Text('Delete', style: TextStyle(color: cs.error)),
          ]),
        ),
      ],
    ).then((value) async {
      if (!context.mounted) return;
      if (value == 'remove_folder') {
        rootScreenKey.currentState?.moveChatOutOfFolder(fav.id);
      } else if (value == 'edit') {
        showDialog<void>(context: context, builder: (_) => _EditChatDialog(fav: fav));
      } else if (value == 'lock') {
        final lockId = 'fav_${fav.id}';
        final set = await showPinDialog(context, PinDialogMode.set, lockId);
        if (!set) return;
        await LockManager.lock(lockId);
      } else if (value == 'unlock') {
        final lockId = 'fav_${fav.id}';
        final ok = await showPinDialog(context, PinDialogMode.verify, lockId);
        if (ok) await LockManager.removeLock(lockId);
      } else if (value == 'delete') {
        _confirmDelete(context, fav);
      }
    });
  }

  Future<void> _openFavWithLockCheck(BuildContext ctx, String favId) async {
    final lockId = 'fav_$favId';
    if (!LockManager.isLocked(lockId)) {
      widget.onOpen(favId);
      return;
    }
    final ok = await showPinDialog(ctx, PinDialogMode.verify, lockId);
    if (ok && mounted) {
      widget.onOpen(favId);
    }
  }

  void _showChatActions(BuildContext context, FavoriteChat fav,
      List<FavFolder> folders) {
    final cs = Theme.of(context).colorScheme;
    final currentFolder =
        folders.where((f) => f.chatIds.contains(fav.id)).firstOrNull;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: SettingsManager.getElementColor(
                cs.surfaceContainerHighest,
                SettingsManager.elementBrightness.value),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.bookmark, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(fav.title,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: cs.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              if (currentFolder != null)
                ListTile(
                  leading: const Icon(Icons.folder_off_outlined),
                  title: Text('Remove from "${currentFolder.name}"'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    rootScreenKey.currentState?.moveChatOutOfFolder(fav.id);
                  },
                ),
              if (folders.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.drive_file_move_outline),
                  title: const Text('Move to folder'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showFolderPicker(context, fav, folders);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showDialog<void>(
                    context: context,
                    builder: (_) => _EditChatDialog(fav: fav),
                  );
                },
              ),
              ValueListenableBuilder<Set<String>>(
                valueListenable: LockManager.lockedChats,
                builder: (_, locked, __) {
                  final lockId = 'fav_${fav.id}';
                  final isLocked = locked.contains(lockId);
                  return ListTile(
                    leading: Icon(
                      isLocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                      color: cs.onSurface,
                    ),
                    title: Text(isLocked ? 'Unlock' : 'Lock'),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      if (isLocked) {
                        final ok = await showPinDialog(context, PinDialogMode.verify, lockId);
                        if (ok) await LockManager.removeLock(lockId);
                      } else {
                        final set = await showPinDialog(context, PinDialogMode.set, lockId);
                        if (!set) return;
                        await LockManager.lock(lockId);
                      }
                    },
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: cs.error),
                title: Text('Delete', style: TextStyle(color: cs.error)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _confirmDelete(context, fav);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showFolderPicker(
      BuildContext context, FavoriteChat fav, List<FavFolder> folders) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: SettingsManager.getElementColor(
                cs.surfaceContainerHighest,
                SettingsManager.elementBrightness.value),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text('Move to folder',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: cs.onSurface)),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView(
                  shrinkWrap: true,
                  children: folders.map((folder) {
                    final isCurrentFolder =
                        folder.chatIds.contains(fav.id);
                    return ListTile(
                      leading: folder.avatarPath != null &&
                              File(folder.avatarPath!).existsSync()
                          ? CircleAvatar(
                              radius: 18,
                              backgroundImage:
                                  FileImage(File(folder.avatarPath!)))
                          : CircleAvatar(
                              radius: 18,
                              backgroundColor: cs.secondaryContainer,
                              child: Icon(Icons.folder,
                                  size: 18, color: cs.secondary)),
                      title: Text(folder.name),
                      subtitle: Text('${folder.chatIds.length} chats',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withValues(alpha: 0.5))),
                      trailing: isCurrentFolder
                          ? Icon(Icons.check, color: cs.primary)
                          : null,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        if (!isCurrentFolder) {
                          rootScreenKey.currentState
                              ?.moveChatToFolder(fav.id, folder.id);
                        }
                      },
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showFolderActions(BuildContext context, FavFolder folder) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: SettingsManager.getElementColor(
                cs.surfaceContainerHighest,
                SettingsManager.elementBrightness.value),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.folder, size: 18, color: cs.secondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(folder.name,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: cs.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showDialog<void>(
                    context: context,
                    builder: (_) => _EditFolderDialog(folder: folder),
                  );
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              ValueListenableBuilder<Set<String>>(
                valueListenable: LockManager.lockedChats,
                builder: (_, locked, __) {
                  final lockId = 'fav_folder_${folder.id}';
                  final isLocked = locked.contains(lockId);
                  return ListTile(
                    leading: Icon(
                      isLocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                      color: cs.onSurface,
                    ),
                    title: Text(isLocked ? 'Unlock folder' : 'Lock folder'),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      if (isLocked) {
                        final ok = await showPinDialog(context, PinDialogMode.verify, lockId);
                        if (ok) await LockManager.removeLock(lockId);
                      } else {
                        final set = await showPinDialog(context, PinDialogMode.set, lockId);
                        if (!set) return;
                        await LockManager.lock(lockId);
                      }
                    },
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: cs.error),
                title: Text('Delete folder',
                    style: TextStyle(color: cs.error)),
                subtitle: const Text('Chats will be moved to top level'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final lockId = 'fav_folder_${folder.id}';
                  if (LockManager.isLocked(lockId)) {
                    final ok = await showPinDialog(
                        context, PinDialogMode.verify, lockId);
                    if (!ok) return;
                  }
                  await LockManager.removeLock(lockId);
                  rootScreenKey.currentState?.deleteFavFolder(folder.id);
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showDesktopFolderContextMenu(
      BuildContext context, Offset pos, FavFolder folder) {
    final cs = Theme.of(context).colorScheme;
    final lockId = 'fav_folder_${folder.id}';
    final isLocked = LockManager.isLocked(lockId);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_outlined, size: 18, color: cs.onSurface),
            const SizedBox(width: 10),
            const Text('Edit'),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'lock',
          child: Row(children: [
            Icon(
              isLocked ? Icons.lock_open_rounded : Icons.lock_rounded,
              size: 18,
              color: cs.onSurface,
            ),
            const SizedBox(width: 10),
            Text(isLocked ? 'Unlock folder' : 'Lock folder'),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline, size: 18, color: cs.error),
            const SizedBox(width: 10),
            Text('Delete folder', style: TextStyle(color: cs.error)),
          ]),
        ),
      ],
    ).then((value) async {
      if (!context.mounted) return;
      if (value == 'edit') {
        showDialog<void>(
            context: context,
            builder: (_) => _EditFolderDialog(folder: folder));
      } else if (value == 'lock') {
        if (isLocked) {
          final ok = await showPinDialog(context, PinDialogMode.verify, lockId);
          if (ok) await LockManager.removeLock(lockId);
        } else {
          final set = await showPinDialog(context, PinDialogMode.set, lockId);
          if (!set) return;
          await LockManager.lock(lockId);
        }
      } else if (value == 'delete') {
        if (isLocked) {
          final ok = await showPinDialog(context, PinDialogMode.verify, lockId);
          if (!ok) return;
        }
        await LockManager.removeLock(lockId);
        rootScreenKey.currentState?.deleteFavFolder(folder.id);
      }
    });
  }

  void _confirmDelete(BuildContext context, FavoriteChat fav) {
    showDialog(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor:
              cs.surface.withValues(alpha: SettingsManager.elementOpacity.value),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Delete chat?'),
          content: Text(
              'Remove "${fav.title}" and all its messages from favorites?'),
          actions: [
            TextButton(
                onPressed: Navigator.of(ctx).pop,
                child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                LockManager.removeLock('fav_${fav.id}');
                widget.onDelete(fav.id);
              },
              child: Text('Delete', style: TextStyle(color: cs.error)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openFolderWithLockCheck(BuildContext ctx, FavFolder folder) async {
    final lockId = 'fav_folder_${folder.id}';
    if (!LockManager.isLocked(lockId)) {
      _openFolder(ctx, folder);
      return;
    }
    final ok = await showPinDialog(ctx, PinDialogMode.verify, lockId);
    if (ok && mounted) {
      _openFolder(ctx, folder);
    }
  }

  void _openFolder(BuildContext context, FavFolder folder) {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      setState(() => _openFolderId = folder.id);
    } else {
      showDialog<void>(
        context: context,
        builder: (_) => _FolderContentDialog(
          folderId: folder.id,
          onOpen: widget.onOpen,
        ),
      );
    }
  }

  // ── Sync sheet ─────────────────────────────────────────────────────────────

  void _showSyncSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: SettingsManager.getElementColor(
                cs.surfaceContainerHighest,
                SettingsManager.elementBrightness.value),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.sync_rounded, size: 20, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text('NearLink',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: cs.onSurface)),
                  ],
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: cs.primaryContainer,
                  child: Icon(Icons.qr_code_rounded,
                      size: 20, color: cs.primary),
                ),
                title: Text(l.nearlinkReceive),
                subtitle: Text(l.nearlinkReceiveSubtitle),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const FavSyncReceiveScreen(),
                  );
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: cs.secondaryContainer,
                  child: Icon(Icons.qr_code_scanner_rounded,
                      size: 20, color: cs.secondary),
                ),
                title: Text(l.nearlinkSend),
                subtitle: Text(l.nearlinkSendSubtitle),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const FavSyncSendScreen(),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder<int>(
      valueListenable: chatsVersion,
      builder: (context, _, __) {
        return ValueListenableBuilder<int>(
          valueListenable: favoritesVersion,
          builder: (context, __, ___) {
            final root = rootScreenKey.currentState;
            final allChats = root?.chats ?? {};
            final favTopOrder = root?.favTopOrder ?? [];
            final favFolders = root?.favFolders ?? [];
            final allFavs = root?.favorites ?? widget.favorites;

            if (_openFolderId != null) {
              final folder = favFolders
                  .where((f) => f.id == _openFolderId)
                  .firstOrNull;
              if (folder == null) {
                WidgetsBinding.instance.addPostFrameCallback(
                    (_) => setState(() => _openFolderId = null));
              } else {
                return _buildInlineFolderView(
                    context, folder, allFavs, allChats);
              }
            }

            if (_editMode) {
              return _buildEditMode(
                  context, favTopOrder, favFolders, allFavs, allChats);
            }
            return _buildNormalMode(
                context, favTopOrder, favFolders, allFavs, allChats);
          },
        );
      },
    );
  }

  // ── Normal mode (ListView) ─────────────────────────────────────────────────

  Widget _buildNormalMode(
    BuildContext context,
    List<String> favTopOrder,
    List<FavFolder> favFolders,
    List<FavoriteChat> allFavs,
    Map<String, List<ChatMessage>> allChats,
  ) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 8 + MediaQuery.paddingOf(context).bottom),
      itemCount: favTopOrder.length + 1,
      cacheExtent: 500,
      physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics()),
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        if (i == 0) return _buildToolbar(context, favTopOrder.isNotEmpty);

        final id = favTopOrder[i - 1];
        final folder = favFolders.where((f) => f.id == id).firstOrNull;

        return FadeTransition(
          opacity: Tween(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(
              parent: _listAnimController,
              curve: Interval(i * _staggerStep, 1.0, curve: Curves.easeOut),
            ),
          ),
          child: folder != null
              ? _buildFolderTile(context, folder, allFavs)
              : _buildChatTile(context, id, allFavs, favFolders, allChats),
        );
      },
    );
  }

  // ── Edit mode (ReorderableListView) ───────────────────────────────────────

  Widget _buildEditMode(
    BuildContext context,
    List<String> favTopOrder,
    List<FavFolder> favFolders,
    List<FavoriteChat> allFavs,
    Map<String, List<ChatMessage>> allChats,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: _buildToolbar(context, favTopOrder.isNotEmpty),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: EdgeInsets.fromLTRB(
                12, 4, 12, 8 + MediaQuery.paddingOf(context).bottom),
            buildDefaultDragHandles: false,
            proxyDecorator: (child, _, __) =>
                Material(color: Colors.transparent, child: child),
            itemCount: favTopOrder.length,
            onReorder: (oldIdx, newIdx) =>
                rootScreenKey.currentState?.reorderFavTop(oldIdx, newIdx),
            itemBuilder: (context, i) {
              final id = favTopOrder[i];
              final folder = favFolders.where((f) => f.id == id).firstOrNull;
              return Padding(
                key: ValueKey(id),
                padding: const EdgeInsets.only(bottom: 6),
                child: folder != null
                    ? _buildFolderTile(context, folder, allFavs,
                        editMode: true, dragIndex: i)
                    : _buildChatTile(context, id, allFavs, favFolders,
                        allChats,
                        editMode: true, dragIndex: i),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Toolbar row ────────────────────────────────────────────────────────────

  Widget _buildToolbar(BuildContext context, bool hasItems) {
    final cs = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
            parent: _listAnimController,
            curve: const Interval(0.0, 1.0, curve: Curves.easeOut)),
      ),
      child: Row(
        children: [
          // Add button
          Expanded(
            child: AdaptiveGlassCard(
              borderRadius: 14,
              padding: EdgeInsets.zero,
              onTap: () => _showAddSheet(context),
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.add, size: 20, color: cs.primary),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Sync button
          AdaptiveGlassCard(
            borderRadius: 14,
            padding: EdgeInsets.zero,
            onTap: () => _showSyncSheet(context),
            child: Container(
              height: 44,
              width: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.sync_rounded, size: 20, color: cs.primary),
            ),
          ),
          // Edit/reorder toggle (only when there's something to reorder)
          if (hasItems) ...[
            const SizedBox(width: 8),
            AdaptiveGlassCard(
              borderRadius: 14,
              padding: EdgeInsets.zero,
              onTap: () => setState(() => _editMode = !_editMode),
              child: Container(
                height: 44,
                width: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _editMode
                      ? Colors.green.withValues(alpha: 0.18)
                      : cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _editMode ? Icons.check_rounded : Icons.sort_rounded,
                  size: 20,
                  color: _editMode ? Colors.green : cs.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Chat tile ──────────────────────────────────────────────────────────────

  Widget _buildChatTile(
    BuildContext context,
    String chatId,
    List<FavoriteChat> allFavs,
    List<FavFolder> favFolders,
    Map<String, List<ChatMessage>> allChats, {
    bool editMode = false,
    int? dragIndex,
  }) {
    final fav = allFavs.where((f) => f.id == chatId).firstOrNull;
    if (fav == null) return const SizedBox.shrink();

    final preview = _getFavPreview(fav.id, allChats);
    final lastTs = _getFavLastTs(fav.id, allChats);
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onSecondaryTapUp: _isDesktop && !editMode
          ? (d) => _showDesktopContextMenu(context, d.globalPosition, fav, favFolders)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: editMode ? null : () => _openFavWithLockCheck(context, fav.id),
        onLongPress: editMode
            ? null
            : () => _showChatActions(context, fav, favFolders),
        child: AdaptiveGlassCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          child: Row(
            children: [
              ValueListenableBuilder<double>(
                valueListenable: SettingsManager.elementBrightness,
                builder: (_, brightness, __) {
                  final baseColor = SettingsManager.getElementColor(
                    cs.surfaceContainerHighest,
                    brightness,
                  );
                  return SizedBox(
                    width: 40,
                    height: 40,
                    child: ClipOval(
                      child: fav.avatarPath != null
                          ? Image.file(File(fav.avatarPath!),
                              fit: BoxFit.cover,
                              width: 40,
                              height: 40,
                              errorBuilder: (_, __, ___) => CircleAvatar(
                                    radius: 20,
                                    backgroundColor: baseColor,
                                    child: Icon(Icons.bookmark,
                                        size: 18, color: cs.primary),
                                  ))
                          : CircleAvatar(
                              radius: 20,
                              backgroundColor: baseColor,
                              child: Icon(Icons.bookmark,
                                  size: 18, color: cs.primary),
                            ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      fav.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    if (preview.isNotEmpty)
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: _isPurplePreview(preview)
                              ? FontWeight.w500
                              : null,
                          color: _isPurplePreview(preview)
                              ? cs.primary
                              : cs.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ),
              if (!editMode)
                ValueListenableBuilder<Set<String>>(
                  valueListenable: LockManager.lockedChats,
                  builder: (_, locked, __) {
                    final isLocked = locked.contains('fav_${fav.id}');
                    if (!isLocked) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.lock_rounded, size: 14,
                          color: cs.onSurface.withValues(alpha: 0.4)),
                    );
                  },
                ),
              if (!editMode && lastTs.millisecondsSinceEpoch > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    _formatTime(lastTs),
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              if (editMode && dragIndex != null)
                ReorderableDragStartListener(
                  index: dragIndex,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.drag_handle_rounded,
                        size: 22,
                        color: cs.onSurface.withValues(alpha: 0.35)),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  // ── Folder tile ────────────────────────────────────────────────────────────

  Widget _buildFolderTile(
    BuildContext context,
    FavFolder folder,
    List<FavoriteChat> allFavs, {
    bool editMode = false,
    int? dragIndex,
  }) {
    final cs = Theme.of(context).colorScheme;
    final count = folder.chatIds.length;

    return GestureDetector(
      onSecondaryTapUp: _isDesktop && !editMode
          ? (d) => _showDesktopFolderContextMenu(context, d.globalPosition, folder)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: editMode ? null : () => _openFolderWithLockCheck(context, folder),
        onLongPress: editMode
            ? null
            : () => _showFolderActions(context, folder),
        child: AdaptiveGlassCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          child: Row(
            children: [
              ValueListenableBuilder<double>(
                valueListenable: SettingsManager.elementBrightness,
                builder: (_, brightness, __) {
                  final baseColor = SettingsManager.getElementColor(
                      cs.surfaceContainerHighest, brightness);
                  return SizedBox(
                    width: 40,
                    height: 40,
                    child: ClipOval(
                      child: folder.avatarPath != null &&
                              File(folder.avatarPath!).existsSync()
                          ? Image.file(File(folder.avatarPath!),
                              fit: BoxFit.cover, width: 40, height: 40)
                          : CircleAvatar(
                              radius: 20,
                              backgroundColor: baseColor,
                              child: Icon(Icons.folder_rounded,
                                  size: 20, color: cs.primary),
                            ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.folder_rounded,
                            size: 14, color: cs.primary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            folder.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w500, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count chat${count == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              if (editMode && dragIndex != null)
                ReorderableDragStartListener(
                  index: dragIndex,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.drag_handle_rounded,
                        size: 22,
                        color: cs.onSurface.withValues(alpha: 0.35)),
                  ),
                ),
              if (!editMode) ...[
                ValueListenableBuilder<Set<String>>(
                  valueListenable: LockManager.lockedChats,
                  builder: (_, locked, __) {
                    final lockId = 'fav_folder_${folder.id}';
                    if (!locked.contains(lockId)) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.lock_rounded,
                          size: 14,
                          color: cs.onSurface.withValues(alpha: 0.45)),
                    );
                  },
                ),
                Icon(Icons.chevron_right_rounded,
                    color: cs.onSurface.withValues(alpha: 0.3)),
              ],
            ],
          ),
        ),
      ),
    ),
    );
  }

  // ── Inline folder view (desktop) ──────────────────────────────────────────

  Widget _buildInlineFolderView(
    BuildContext context,
    FavFolder folder,
    List<FavoriteChat> allFavs,
    Map<String, List<ChatMessage>> allChats,
  ) {
    final cs = Theme.of(context).colorScheme;
    final folderChats = folder.chatIds
        .map((id) => allFavs.where((f) => f.id == id).firstOrNull)
        .whereType<FavoriteChat>()
        .toList();
    final displayChats = folderChats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with back button
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() {
                  _openFolderId = null;
                  _editMode = false;
                }),
                tooltip: 'Back',
              ),
              SizedBox(
                width: 28,
                height: 28,
                child: ClipOval(
                  child: folder.avatarPath != null &&
                          File(folder.avatarPath!).existsSync()
                      ? Image.file(File(folder.avatarPath!),
                          fit: BoxFit.cover, width: 28, height: 28)
                      : CircleAvatar(
                          radius: 14,
                          backgroundColor: cs.secondaryContainer,
                          child: Icon(Icons.folder_rounded,
                              size: 14, color: cs.secondary),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  folder.name,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (folderChats.isNotEmpty)
                IconButton(
                  icon: Icon(
                    _editMode ? Icons.check_rounded : Icons.sort_rounded,
                    color: _editMode ? Colors.green : cs.primary,
                  ),
                  onPressed: () => setState(() => _editMode = !_editMode),
                  tooltip: _editMode ? 'Done' : 'Reorder',
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Content
        Expanded(
          child: folderChats.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No chats in this folder yet.\nLong-press a chat and choose "Move to folder".',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.5),
                          height: 1.5,
                          fontSize: 13),
                    ),
                  ),
                )
              : _editMode
                  ? _buildInlineReorderList(
                      context, folder, displayChats, allChats, cs)
                  : _buildInlineNormalList(
                      context, displayChats, allChats, cs),
        ),
      ],
    );
  }

  Widget _buildInlineNormalList(
      BuildContext context,
      List<FavoriteChat> chats,
      Map<String, List<ChatMessage>> allChats,
      ColorScheme cs) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 8 + MediaQuery.paddingOf(context).bottom),
      itemCount: chats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) =>
          _buildInlineChatRow(context, chats[i], allChats, cs),
    );
  }

  Widget _buildInlineReorderList(
      BuildContext context,
      FavFolder folder,
      List<FavoriteChat> chats,
      Map<String, List<ChatMessage>> allChats,
      ColorScheme cs) {
    return ReorderableListView.builder(
      padding: EdgeInsets.fromLTRB(
          12, 4, 12, 8 + MediaQuery.paddingOf(context).bottom),
      proxyDecorator: (child, _, __) =>
          Material(color: Colors.transparent, child: child),
      itemCount: chats.length,
      onReorder: (oldIdx, newIdx) {
        var newIdx0 = newIdx;
        if (newIdx0 > oldIdx) newIdx0--;
        final ids = chats.map((c) => c.id).toList();
        final item = ids.removeAt(oldIdx);
        ids.insert(newIdx0, item);
        rootScreenKey.currentState?.setFolderChatOrder(folder.id, ids);
      },
      itemBuilder: (context, i) => Padding(
        key: ValueKey(chats[i].id),
        padding: const EdgeInsets.only(bottom: 6),
        child: _buildInlineChatRow(context, chats[i], allChats, cs,
            editMode: true),
      ),
    );
  }

  Widget _buildInlineChatRow(
      BuildContext context,
      FavoriteChat fav,
      Map<String, List<ChatMessage>> allChats,
      ColorScheme cs, {
      bool editMode = false}) {
    final preview = _getFavPreview(fav.id, allChats);
    final lastTs = _getFavLastTs(fav.id, allChats);

    return GestureDetector(
      onSecondaryTapUp: _isDesktop && !editMode
          ? (d) => _showDesktopInlineContextMenu(context, d.globalPosition, fav, cs)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: editMode ? null : () => _openFavWithLockCheck(context, fav.id),
        onLongPress: editMode
            ? null
            : () => _showInlineChatActions(context, fav, cs),
        child: AdaptiveGlassCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          child: Row(
            children: [
              ValueListenableBuilder<double>(
                valueListenable: SettingsManager.elementBrightness,
                builder: (_, brightness, __) {
                  final baseColor = SettingsManager.getElementColor(
                      cs.surfaceContainerHighest, brightness);
                  return SizedBox(
                    width: 40,
                    height: 40,
                    child: ClipOval(
                      child: fav.avatarPath != null
                          ? Image.file(File(fav.avatarPath!),
                              fit: BoxFit.cover,
                              width: 40,
                              height: 40,
                              errorBuilder: (_, __, ___) => CircleAvatar(
                                    radius: 20,
                                    backgroundColor: baseColor,
                                    child: Icon(Icons.bookmark,
                                        size: 18, color: cs.primary),
                                  ))
                          : CircleAvatar(
                              radius: 20,
                              backgroundColor: baseColor,
                              child: Icon(Icons.bookmark,
                                  size: 18, color: cs.primary)),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(fav.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w500, fontSize: 15)),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: _isPurplePreview(preview)
                              ? FontWeight.w500
                              : null,
                          color: _isPurplePreview(preview)
                              ? cs.primary
                              : cs.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ValueListenableBuilder<Set<String>>(
                valueListenable: LockManager.lockedChats,
                builder: (_, locked, __) {
                  final isLocked = locked.contains('fav_${fav.id}');
                  if (!isLocked) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.lock_rounded, size: 14,
                        color: cs.onSurface.withValues(alpha: 0.4)),
                  );
                },
              ),
              if (!editMode && lastTs.millisecondsSinceEpoch > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    _formatTime(lastTs),
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.6)),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  void _showInlineChatActions(
      BuildContext context, FavoriteChat fav, ColorScheme cs) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: SettingsManager.getElementColor(
                cs.surfaceContainerHighest,
                SettingsManager.elementBrightness.value),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  Icon(Icons.bookmark, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(fav.title,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: cs.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                ]),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.folder_off_outlined),
                title: const Text('Remove from folder'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  rootScreenKey.currentState?.moveChatOutOfFolder(fav.id);
                },
              ),
              ValueListenableBuilder<Set<String>>(
                valueListenable: LockManager.lockedChats,
                builder: (_, locked, __) {
                  final lockId = 'fav_${fav.id}';
                  final isLocked = locked.contains(lockId);
                  return ListTile(
                    leading: Icon(
                      isLocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                      color: cs.onSurface,
                    ),
                    title: Text(isLocked ? 'Unlock' : 'Lock'),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      if (isLocked) {
                        final ok = await showPinDialog(context, PinDialogMode.verify, lockId);
                        if (ok) await LockManager.removeLock(lockId);
                      } else {
                        final set = await showPinDialog(context, PinDialogMode.set, lockId);
                        if (!set) return;
                        await LockManager.lock(lockId);
                      }
                    },
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: cs.error),
                title: Text('Delete', style: TextStyle(color: cs.error)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showDialog(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      title: const Text('Delete chat?'),
                      content:
                          Text('Remove "${fav.title}" and all its messages?'),
                      actions: [
                        TextButton(
                            onPressed: Navigator.of(dCtx).pop,
                            child: const Text('Cancel')),
                        TextButton(
                          onPressed: () {
                            Navigator.of(dCtx).pop();
                            LockManager.removeLock('fav_${fav.id}');
                            rootScreenKey.currentState
                                ?.deleteFavoriteById(fav.id);
                          },
                          child:
                              Text('Delete', style: TextStyle(color: cs.error)),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

}

// ── Folder content dialog ──────────────────────────────────────────────────────

class _FolderContentDialog extends StatefulWidget {
  final String folderId;
  final void Function(String id) onOpen;

  const _FolderContentDialog({
    required this.folderId,
    required this.onOpen,
  });

  @override
  State<_FolderContentDialog> createState() => _FolderContentDialogState();
}

class _FolderContentDialogState extends State<_FolderContentDialog> {
  bool _editMode = false;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Future<void> _openWithLockCheck(BuildContext ctx, String favId) async {
    final lockId = 'fav_$favId';
    if (!LockManager.isLocked(lockId)) {
      widget.onOpen(favId);
      return;
    }
    final ok = await showPinDialog(ctx, PinDialogMode.verify, lockId);
    if (ok && mounted) {
      widget.onOpen(favId);
    }
  }

  void _showDesktopContextMenu(
      BuildContext context, Offset pos, FavoriteChat fav, ColorScheme cs) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem<String>(
          value: 'remove_folder',
          child: Row(children: [
            Icon(Icons.folder_off_outlined, size: 18, color: cs.onSurface),
            const SizedBox(width: 10),
            const Text('Remove from folder'),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_outlined, size: 18, color: cs.onSurface),
            const SizedBox(width: 10),
            const Text('Edit'),
          ]),
        ),
        PopupMenuItem<String>(
          value: LockManager.isLocked('fav_${fav.id}') ? 'unlock' : 'lock',
          child: Row(children: [
            Icon(
              LockManager.isLocked('fav_${fav.id}') ? Icons.lock_open_rounded : Icons.lock_rounded,
              size: 18, color: cs.onSurface,
            ),
            const SizedBox(width: 10),
            Text(LockManager.isLocked('fav_${fav.id}') ? 'Unlock' : 'Lock'),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline, size: 18, color: cs.error),
            const SizedBox(width: 10),
            Text('Delete', style: TextStyle(color: cs.error)),
          ]),
        ),
      ],
    ).then((value) async {
      if (!context.mounted) return;
      if (value == 'remove_folder') {
        rootScreenKey.currentState?.moveChatOutOfFolder(fav.id);
      } else if (value == 'edit') {
        showDialog<void>(
            context: context, builder: (_) => _EditChatDialog(fav: fav));
      } else if (value == 'lock') {
        final lockId = 'fav_${fav.id}';
        final set = await showPinDialog(context, PinDialogMode.set, lockId);
        if (!set) return;
        await LockManager.lock(lockId);
      } else if (value == 'unlock') {
        final lockId = 'fav_${fav.id}';
        final ok = await showPinDialog(context, PinDialogMode.verify, lockId);
        if (ok) await LockManager.removeLock(lockId);
      } else if (value == 'delete') {
        showDialog(
          context: context,
          builder: (dCtx) => AlertDialog(
            title: const Text('Delete chat?'),
            content: Text('Remove "${fav.title}" and all its messages?'),
            actions: [
              TextButton(
                  onPressed: Navigator.of(dCtx).pop,
                  child: const Text('Cancel')),
              TextButton(
                onPressed: () {
                  Navigator.of(dCtx).pop();
                  LockManager.removeLock('fav_${fav.id}');
                  rootScreenKey.currentState?.deleteFavoriteById(fav.id);
                },
                child: Text('Delete', style: TextStyle(color: cs.error)),
              ),
            ],
          ),
        );
      }
    });
  }

  void _showChatActions(BuildContext context, FavoriteChat fav,
      ColorScheme cs) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: SettingsManager.getElementColor(
                cs.surfaceContainerHighest,
                SettingsManager.elementBrightness.value),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                child: Row(children: [
                  Icon(Icons.bookmark, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(fav.title,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: cs.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                ]),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.folder_off_outlined),
                title: const Text('Remove from folder'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  rootScreenKey.currentState?.moveChatOutOfFolder(fav.id);
                },
              ),
              ValueListenableBuilder<Set<String>>(
                valueListenable: LockManager.lockedChats,
                builder: (_, locked, __) {
                  final lockId = 'fav_${fav.id}';
                  final isLocked = locked.contains(lockId);
                  return ListTile(
                    leading: Icon(
                      isLocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                      color: cs.onSurface,
                    ),
                    title: Text(isLocked ? 'Unlock' : 'Lock'),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      if (isLocked) {
                        final ok = await showPinDialog(context, PinDialogMode.verify, lockId);
                        if (ok) await LockManager.removeLock(lockId);
                      } else {
                        final set = await showPinDialog(context, PinDialogMode.set, lockId);
                        if (!set) return;
                        await LockManager.lock(lockId);
                      }
                    },
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: cs.error),
                title: Text('Delete', style: TextStyle(color: cs.error)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showDialog(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      title: const Text('Delete chat?'),
                      content: Text(
                          'Remove "${fav.title}" and all its messages?'),
                      actions: [
                        TextButton(
                            onPressed: Navigator.of(dCtx).pop,
                            child: const Text('Cancel')),
                        TextButton(
                          onPressed: () {
                            Navigator.of(dCtx).pop();
                            LockManager.removeLock('fav_${fav.id}');
                            rootScreenKey.currentState
                                ?.deleteFavoriteById(fav.id);
                          },
                          child: Text('Delete',
                              style: TextStyle(color: cs.error)),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ValueListenableBuilder<int>(
        valueListenable: chatsVersion,
        builder: (_, __, ___) => ValueListenableBuilder<int>(
        valueListenable: favoritesVersion,
        builder: (_, __, ___) {
          final root = rootScreenKey.currentState;
          final folder = root?.favFolders
              .where((f) => f.id == widget.folderId)
              .firstOrNull;

          if (folder == null) {
            // Folder was deleted while open
            WidgetsBinding.instance
                .addPostFrameCallback((_) => Navigator.of(context).pop());
            return const SizedBox(width: 400, height: 100,
                child: Center(child: CircularProgressIndicator()));
          }

          final allFavs = root?.favorites ?? [];
          final allChats = root?.chats ?? {};

          final folderChats = folder.chatIds
              .map((id) => allFavs.where((f) => f.id == id).firstOrNull)
              .whereType<FavoriteChat>()
              .toList();
          final displayChats = folderChats;

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title bar
                Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    border: Border(
                      bottom: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.3)),
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: ClipOval(
                          child: folder.avatarPath != null &&
                                  File(folder.avatarPath!).existsSync()
                              ? Image.file(File(folder.avatarPath!),
                                  fit: BoxFit.cover, width: 36, height: 36)
                              : CircleAvatar(
                                  radius: 18,
                                  backgroundColor: cs.secondaryContainer,
                                  child: Icon(Icons.folder_rounded,
                                      size: 18, color: cs.secondary),
                                ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          folder.name,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (folderChats.isNotEmpty)
                        IconButton(
                          icon: Icon(
                            _editMode
                                ? Icons.check_rounded
                                : Icons.sort_rounded,
                            color: _editMode ? Colors.green : cs.primary,
                          ),
                          onPressed: () =>
                              setState(() => _editMode = !_editMode),
                          tooltip: _editMode ? 'Done' : 'Reorder',
                        ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                // Content
                Expanded(
                  child: folderChats.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text('No chats in this folder yet.\n'
                                'Long-press a chat and choose "Move to folder".',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: cs.onSurface
                                        .withValues(alpha: 0.5),
                                    height: 1.5)),
                          ),
                        )
                      : _editMode
                          ? _buildReorderList(
                              context, folder, displayChats, allChats, cs)
                          : _buildNormalList(
                              context, displayChats, allChats, cs),
                ),
              ],
            ),
          );
        },
        ),
      ),
    );
  }

  Widget _buildNormalList(
      BuildContext context,
      List<FavoriteChat> chats,
      Map<String, List<ChatMessage>> allChats,
      ColorScheme cs) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: chats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final fav = chats[i];
        return _buildChatRow(context, fav, allChats, cs);
      },
    );
  }

  Widget _buildReorderList(
      BuildContext context,
      FavFolder folder,
      List<FavoriteChat> chats,
      Map<String, List<ChatMessage>> allChats,
      ColorScheme cs) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      buildDefaultDragHandles: false,
      proxyDecorator: (child, _, __) =>
          Material(color: Colors.transparent, child: child),
      itemCount: chats.length,
      onReorder: (oldIdx, newIdx) {
        var newIdx0 = newIdx;
        if (newIdx0 > oldIdx) newIdx0--;
        final ids = chats.map((c) => c.id).toList();
        final item = ids.removeAt(oldIdx);
        ids.insert(newIdx0, item);
        rootScreenKey.currentState?.setFolderChatOrder(folder.id, ids);
      },
      itemBuilder: (context, i) {
        final fav = chats[i];
        return Padding(
          key: ValueKey(fav.id),
          padding: const EdgeInsets.only(bottom: 6),
          child: _buildChatRow(context, fav, allChats, cs,
              editMode: true, dragIndex: i),
        );
      },
    );
  }

  Widget _buildChatRow(
      BuildContext context,
      FavoriteChat fav,
      Map<String, List<ChatMessage>> allChats,
      ColorScheme cs, {
      bool editMode = false,
      int? dragIndex}) {
    final preview = _getFavPreview(fav.id, allChats);
    final lastTs = _getFavLastTs(fav.id, allChats);

    return GestureDetector(
      onSecondaryTapUp: _isDesktop && !editMode
          ? (d) => _showDesktopContextMenu(context, d.globalPosition, fav, cs)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: editMode ? null : () => _openWithLockCheck(context, fav.id),
        onLongPress:
            editMode ? null : () => _showChatActions(context, fav, cs),
        child: AdaptiveGlassCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          child: Row(
            children: [
              ValueListenableBuilder<double>(
                valueListenable: SettingsManager.elementBrightness,
                builder: (_, brightness, __) {
                  final baseColor = SettingsManager.getElementColor(
                      cs.surfaceContainerHighest, brightness);
                  return SizedBox(
                    width: 40,
                    height: 40,
                    child: ClipOval(
                      child: fav.avatarPath != null
                          ? Image.file(File(fav.avatarPath!),
                              fit: BoxFit.cover,
                              width: 40,
                              height: 40,
                              errorBuilder: (_, __, ___) => CircleAvatar(
                                    radius: 20,
                                    backgroundColor: baseColor,
                                    child: Icon(Icons.bookmark,
                                        size: 18, color: cs.primary),
                                  ))
                          : CircleAvatar(
                              radius: 20,
                              backgroundColor: baseColor,
                              child: Icon(Icons.bookmark,
                                  size: 18, color: cs.primary)),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(fav.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w500, fontSize: 15)),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: _isPurplePreview(preview)
                              ? FontWeight.w500
                              : null,
                          color: _isPurplePreview(preview)
                              ? cs.primary
                              : cs.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!editMode)
                ValueListenableBuilder<Set<String>>(
                  valueListenable: LockManager.lockedChats,
                  builder: (_, locked, __) {
                    final isLocked = locked.contains('fav_${fav.id}');
                    if (!isLocked) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.lock_rounded, size: 14,
                          color: cs.onSurface.withValues(alpha: 0.4)),
                    );
                  },
                ),
              if (!editMode && lastTs.millisecondsSinceEpoch > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    _formatTime(lastTs),
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              if (editMode && dragIndex != null)
                ReorderableDragStartListener(
                  index: dragIndex,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.drag_handle_rounded,
                        size: 22,
                        color: cs.onSurface.withValues(alpha: 0.35)),
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

// ── Edit chat dialog ──────────────────────────────────────────────────────────

class _EditChatDialog extends StatefulWidget {
  final FavoriteChat fav;
  const _EditChatDialog({required this.fav});

  @override
  State<_EditChatDialog> createState() => _EditChatDialogState();
}

class _EditChatDialogState extends State<_EditChatDialog> {
  late final TextEditingController _nameCtrl;
  late String? _avatarPath;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.fav.title);
    _avatarPath = widget.fav.avatarPath;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 85);
    if (picked == null || !mounted) return;
    setState(() => _isUploading = true);
    try {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      final cropped = await showAvatarCropScreen(context, bytes);
      if (cropped == null) { setState(() => _isUploading = false); return; }
      final dir = Directory(
          '${(await getApplicationSupportDirectory()).path}/fav_avatars');
      await dir.create(recursive: true);
      final hash = md5.convert(cropped).toString().substring(0, 12);
      final path = '${dir.path}/${widget.fav.id}_$hash.jpg';
      await File(path).writeAsBytes(cropped);
      if (!mounted) return;
      setState(() { _avatarPath = path; _isUploading = false; });
    } catch (_) {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _removeAvatar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove avatar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true && mounted) setState(() => _avatarPath = null);
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final updated = widget.fav.copyWith(title: name, avatarPath: _avatarPath);
    rootScreenKey.currentState?.updateFavorite(updated);
    rootScreenKey.currentState?.saveFavorites();
    favoritesVersion.value++;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<double>(
      valueListenable: SettingsManager.elementBrightness,
      builder: (_, brightness, __) {
        final fillColor = SettingsManager.getElementColor(
            cs.surfaceContainerHighest, brightness);
        return AlertDialog(
          backgroundColor:
              cs.surface.withValues(alpha: SettingsManager.elementOpacity.value),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit chat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _isUploading ? null : _pickAvatar,
                  onLongPress: _avatarPath != null ? _removeAvatar : null,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: cs.outline.withValues(alpha: 0.2), width: 2),
                        ),
                        child: ClipOval(
                          child: _avatarPath != null &&
                                  File(_avatarPath!).existsSync()
                              ? Image.file(File(_avatarPath!), fit: BoxFit.cover)
                              : Container(
                                  color: fillColor.withValues(alpha: 0.3),
                                  child: Icon(Icons.bookmark,
                                      size: 48, color: cs.primary),
                                ),
                        ),
                      ),
                      if (_isUploading)
                        Container(
                          width: 100,
                          height: 100,
                          decoration: const BoxDecoration(
                              color: Colors.black54, shape: BoxShape.circle),
                          child: const Center(
                              child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                maxLength: 50,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: 'Chat name',
                  counterText: '',
                  filled: true,
                  fillColor: fillColor.withValues(alpha: 0.3),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: _isUploading ? null : _save,
                child: const Text('Save')),
          ],
        );
      },
    );
  }
}

// ── Edit folder dialog ────────────────────────────────────────────────────────

class _EditFolderDialog extends StatefulWidget {
  final FavFolder folder;
  const _EditFolderDialog({required this.folder});

  @override
  State<_EditFolderDialog> createState() => _EditFolderDialogState();
}

class _EditFolderDialogState extends State<_EditFolderDialog> {
  late final TextEditingController _nameCtrl;
  late String? _avatarPath;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.folder.name);
    _avatarPath = widget.folder.avatarPath;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 85);
    if (picked == null || !mounted) return;
    setState(() => _isUploading = true);
    try {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      final cropped = await showAvatarCropScreen(context, bytes);
      if (cropped == null) { setState(() => _isUploading = false); return; }
      final dir = Directory(
          '${(await getApplicationSupportDirectory()).path}/fav_folder_avatars');
      await dir.create(recursive: true);
      final hash = md5.convert(cropped).toString().substring(0, 12);
      final path = '${dir.path}/${widget.folder.id}_$hash.jpg';
      await File(path).writeAsBytes(cropped);
      if (!mounted) return;
      setState(() { _avatarPath = path; _isUploading = false; });
    } catch (_) {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _removeAvatar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove avatar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true && mounted) setState(() => _avatarPath = null);
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final root = rootScreenKey.currentState;
    if (name != widget.folder.name) root?.renameFavFolder(widget.folder.id, name);
    if (_avatarPath != widget.folder.avatarPath) {
      root?.setFavFolderAvatar(widget.folder.id, _avatarPath);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<double>(
      valueListenable: SettingsManager.elementBrightness,
      builder: (_, brightness, __) {
        final fillColor = SettingsManager.getElementColor(
            cs.surfaceContainerHighest, brightness);
        return AlertDialog(
          backgroundColor:
              cs.surface.withValues(alpha: SettingsManager.elementOpacity.value),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit folder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _isUploading ? null : _pickAvatar,
                  onLongPress: _avatarPath != null ? _removeAvatar : null,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: cs.outline.withValues(alpha: 0.2), width: 2),
                        ),
                        child: ClipOval(
                          child: _avatarPath != null &&
                                  File(_avatarPath!).existsSync()
                              ? Image.file(File(_avatarPath!), fit: BoxFit.cover)
                              : Container(
                                  color: cs.secondaryContainer
                                      .withValues(alpha: 0.6),
                                  child: Icon(Icons.folder_rounded,
                                      size: 48, color: cs.secondary),
                                ),
                        ),
                      ),
                      if (_isUploading)
                        Container(
                          width: 100,
                          height: 100,
                          decoration: const BoxDecoration(
                              color: Colors.black54, shape: BoxShape.circle),
                          child: const Center(
                              child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                maxLength: 50,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: 'Folder name',
                  counterText: '',
                  filled: true,
                  fillColor: fillColor.withValues(alpha: 0.3),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: _isUploading ? null : _save,
                child: const Text('Save')),
          ],
        );
      },
    );
  }
}

// ── New folder dialog ─────────────────────────────────────────────────────────

class _NewFolderDialog extends StatefulWidget {
  const _NewFolderDialog();

  @override
  State<_NewFolderDialog> createState() => _NewFolderDialogState();
}

class _NewFolderDialogState extends State<_NewFolderDialog> {
  final _nameCtrl = TextEditingController();
  String? _avatarPath;
  bool _isUploading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 85);
    if (picked == null || !mounted) return;
    setState(() => _isUploading = true);
    try {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      final cropped = await showAvatarCropScreen(context, bytes);
      if (cropped == null) { setState(() => _isUploading = false); return; }
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final dir = Directory(
          '${(await getApplicationSupportDirectory()).path}/fav_folder_avatars');
      await dir.create(recursive: true);
      final hash = md5.convert(cropped).toString().substring(0, 12);
      final path = '${dir.path}/${id}_$hash.jpg';
      await File(path).writeAsBytes(cropped);
      if (!mounted) return;
      setState(() { _avatarPath = path; _isUploading = false; });
    } catch (_) {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _create() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    rootScreenKey.currentState?.createFavFolder(name, avatarPath: _avatarPath);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<double>(
      valueListenable: SettingsManager.elementBrightness,
      builder: (_, brightness, __) {
        final fillColor = SettingsManager.getElementColor(
            cs.surfaceContainerHighest, brightness);
        return AlertDialog(
          backgroundColor:
              cs.surface.withValues(alpha: SettingsManager.elementOpacity.value),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('New folder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _isUploading ? null : _pickAvatar,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: cs.outline.withValues(alpha: 0.2), width: 2),
                        ),
                        child: ClipOval(
                          child: _avatarPath != null && File(_avatarPath!).existsSync()
                              ? Image.file(File(_avatarPath!), fit: BoxFit.cover)
                              : Container(
                                  color: cs.secondaryContainer.withValues(alpha: 0.6),
                                  child: Icon(Icons.folder_rounded,
                                      size: 48, color: cs.secondary),
                                ),
                        ),
                      ),
                      if (_isUploading)
                        Container(
                          width: 100,
                          height: 100,
                          decoration: const BoxDecoration(
                              color: Colors.black54, shape: BoxShape.circle),
                          child: const Center(
                              child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                maxLength: 50,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _create(),
                decoration: InputDecoration(
                  labelText: 'Folder name',
                  counterText: '',
                  filled: true,
                  fillColor: fillColor.withValues(alpha: 0.3),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: _isUploading ? null : _create,
                child: const Text('Create')),
          ],
        );
      },
    );
  }
}

// ── New chat dialog ───────────────────────────────────────────────────────────

class _NewChatDialog extends StatefulWidget {
  final void Function(FavoriteChat) onAdd;
  const _NewChatDialog({required this.onAdd});

  @override
  State<_NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends State<_NewChatDialog> {
  final _nameCtrl = TextEditingController();
  String? _avatarPath;
  bool _isUploading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 85);
    if (picked == null || !mounted) return;
    setState(() => _isUploading = true);
    try {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      final cropped = await showAvatarCropScreen(context, bytes);
      if (cropped == null) { setState(() => _isUploading = false); return; }
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final dir = Directory(
          '${(await getApplicationSupportDirectory()).path}/fav_avatars');
      await dir.create(recursive: true);
      final hash = md5.convert(cropped).toString().substring(0, 12);
      final path = '${dir.path}/${id}_${hash}.jpg';
      await File(path).writeAsBytes(cropped);
      if (!mounted) return;
      setState(() { _avatarPath = path; _isUploading = false; });
    } catch (_) {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _create() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final fav = FavoriteChat.create(name).copyWith(avatarPath: _avatarPath);
    widget.onAdd(fav);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<double>(
      valueListenable: SettingsManager.elementBrightness,
      builder: (_, brightness, __) {
        final fillColor = SettingsManager.getElementColor(
            cs.surfaceContainerHighest, brightness);
        return AlertDialog(
          backgroundColor:
              cs.surface.withValues(alpha: SettingsManager.elementOpacity.value),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('New chat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _isUploading ? null : _pickAvatar,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: cs.outline.withValues(alpha: 0.2), width: 2),
                        ),
                        child: ClipOval(
                          child: _avatarPath != null && File(_avatarPath!).existsSync()
                              ? Image.file(File(_avatarPath!), fit: BoxFit.cover)
                              : Container(
                                  color: fillColor.withValues(alpha: 0.3),
                                  child: Icon(Icons.bookmark,
                                      size: 48, color: cs.primary),
                                ),
                        ),
                      ),
                      if (_isUploading)
                        Container(
                          width: 100,
                          height: 100,
                          decoration: const BoxDecoration(
                              color: Colors.black54, shape: BoxShape.circle),
                          child: const Center(
                              child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                maxLength: 50,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _create(),
                decoration: InputDecoration(
                  labelText: 'Chat name',
                  counterText: '',
                  filled: true,
                  fillColor: fillColor.withValues(alpha: 0.3),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: _isUploading ? null : _create,
                child: const Text('Create')),
          ],
        );
      },
    );
  }
}
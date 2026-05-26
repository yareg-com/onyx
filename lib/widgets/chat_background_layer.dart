// lib/widgets/chat_background_layer.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../managers/settings_manager.dart';
import 'adaptive_blur.dart';

/// Drop-in Positioned.fill widget that renders the chat background.
/// Handles both image (with optional blur) and video wallpapers.
class ChatBackgroundLayer extends StatelessWidget {
  const ChatBackgroundLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: SettingsManager.chatVideoBackground,
      builder: (_, videoPath, __) {
        if (videoPath != null && File(videoPath).existsSync()) {
          return Positioned.fill(
            child: IgnorePointer(
              child: _VideoBackground(path: videoPath),
            ),
          );
        }
        return ValueListenableBuilder<String?>(
          valueListenable: SettingsManager.chatBackground,
          builder: (_, path, __) {
            if (path == null) return const SizedBox.shrink();
            final f = File(path);
            if (!f.existsSync()) return const SizedBox.shrink();
            return ValueListenableBuilder<bool>(
              valueListenable: SettingsManager.blurBackground,
              builder: (_, blur, __) {
                return ValueListenableBuilder<double>(
                  valueListenable: SettingsManager.blurSigma,
                  builder: (_, sigma, __) {
                    final provider = FileImage(f);
                    final child = blur
                        ? AdaptiveBlur(imageProvider: provider, sigma: sigma, fit: BoxFit.cover)
                        : Image(image: provider, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
                    return Positioned.fill(
                      child: IgnorePointer(
                        child: Opacity(opacity: 0.95, child: child),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _VideoBackground extends StatefulWidget {
  final String path;
  const _VideoBackground({required this.path});

  @override
  State<_VideoBackground> createState() => _VideoBackgroundState();
}

class _VideoBackgroundState extends State<_VideoBackground> {
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.setPlaylistMode(PlaylistMode.loop);
    _player.setVolume(0);
    _player.open(Media(widget.path));
  }

  @override
  void didUpdateWidget(_VideoBackground old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _player.open(Media(widget.path));
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.95,
      child: Video(
        controller: _controller,
        fit: BoxFit.cover,
        controls: NoVideoControls,
      ),
    );
  }
}

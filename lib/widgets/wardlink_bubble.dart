// lib/widgets/wardlink_bubble.dart
//
// Floats above all screens (same Stack level as VinylPlayerButton in
// MaterialApp.builder). Visible only when a WardLink transfer is minimized.
// Draggable, tap = reopen dialog, auto-dismisses 2 s after transfer completes.

import 'dart:math' show pi;
import 'package:flutter/material.dart';
import '../globals.dart' show navigatorKey;
import '../utils/wardlink_bubble_controller.dart';
import '../screens/fav_sync_receive_screen.dart';
import '../screens/fav_sync_send_screen.dart';

class WardLinkBubble extends StatefulWidget {
  const WardLinkBubble({super.key});

  @override
  State<WardLinkBubble> createState() => _WardLinkBubbleState();
}

class _WardLinkBubbleState extends State<WardLinkBubble>
    with TickerProviderStateMixin {
  // Continuous forward spin for the sync icon.
  late final AnimationController _spin;
  // Pulsating glow opacity (0 → 1 → 0).
  late final AnimationController _pulse;
  Offset? _pos;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    wardLinkBubbleController.addListener(_onChanged);
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    wardLinkBubbleController.removeListener(_onChanged);
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _onTap() {
    final ctrl = wardLinkBubbleController;
    if (ctrl.phase == WardLinkBubblePhase.done) {
      ctrl.reset();
      return;
    }
    // Reopen the dialog.
    ctrl.unminimize();
    final navCtx = navigatorKey.currentState?.overlay?.context;
    if (navCtx == null) return;
    if (ctrl.isSend) {
      showDialog(
        context: navCtx,
        barrierDismissible: false,
        builder: (_) => const FavSyncSendScreen(),
      );
    } else {
      showDialog(
        context: navCtx,
        barrierDismissible: false,
        builder: (_) => const FavSyncReceiveScreen(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = wardLinkBubbleController;
    if (!ctrl.isMinimized) return const SizedBox.shrink();
    if (ctrl.total == 0 && ctrl.phase != WardLinkBubblePhase.done) return const SizedBox.shrink();

    final mq = MediaQuery.of(context);
    _pos ??= Offset(mq.size.width - 74, mq.viewPadding.top + 170);

    final cs = Theme.of(context).colorScheme;
    final isDone = ctrl.phase == WardLinkBubblePhase.done;

    return Positioned(
      left: _pos!.dx,
      top: _pos!.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) {
          setState(() {
            _pos = Offset(
              (_pos!.dx + d.delta.dx).clamp(0.0, mq.size.width - 58),
              (_pos!.dy + d.delta.dy)
                  .clamp(mq.viewPadding.top, mq.size.height - 100),
            );
          });
        },
        onTap: _onTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_spin, _pulse]),
          builder: (_, __) {
            final glow = isDone ? 0.0 : 0.25 + _pulse.value * 0.35;
            return Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? cs.primary : cs.primaryContainer,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: cs.primary.withValues(alpha: glow),
                    blurRadius: 22,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: isDone
                  ? Icon(
                      Icons.check_rounded,
                      size: 28,
                      color: cs.onPrimary,
                    )
                  : Transform.rotate(
                      angle: _spin.value * 2 * pi,
                      child: Icon(
                        Icons.sync_rounded,
                        size: 28,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }
}

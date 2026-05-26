// lib/utils/nearlink_bubble_controller.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/lan_fav_sync_service.dart';

enum NearLinkBubblePhase { idle, transferring, done }

class NearLinkBubbleController extends ChangeNotifier {
  NearLinkBubblePhase _phase = NearLinkBubblePhase.idle;
  bool _minimized = false;

  int current = 0;
  int total = 0;
  String statusText = '';
  bool isSend = false;
  String? receiveQrJson;

  // Held alive during minimize so the TCP server doesn't get closed.
  LanFavSyncReceiverSession? _receiverSession;

  // Send stream subscription held when minimized (so we can cancel on demand).
  StreamSubscription<LanFavSyncEvent>? _sendSub;

  // Desktop sender handshake session — held so dispose() doesn't close it.
  LanFavSyncSenderHandshakeSession? _senderHandshakeSession;

  NearLinkBubblePhase get phase => _phase;
  bool get isActive => _phase != NearLinkBubblePhase.idle;
  bool get isMinimized => _minimized;

  // ── Called by receive screen after server is ready ─────────────────────────

  void beginReceive(LanFavSyncReceiverSession session) {
    _receiverSession = session;
    receiveQrJson = session.qrJson;
    isSend = false;
    _phase = NearLinkBubblePhase.transferring;
    _minimized = false;
    current = 0;
    total = 0;
    statusText = '';
    notifyListeners();
  }

  // ── Called by send screen when transfer starts ─────────────────────────────

  void beginSend() {
    isSend = true;
    _phase = NearLinkBubblePhase.transferring;
    _minimized = false;
    current = 0;
    total = 0;
    statusText = '';
    notifyListeners();
  }

  // ── Forward events from screen's _onEvent ─────────────────────────────────
  // Screen calls this BEFORE its own mounted check so events reach the
  // controller even after the dialog has been minimized and popped.

  void processEvent(LanFavSyncEvent event) {
    if (event is LanFavSyncStatus) {
      current = event.current;
      total = event.total;
      statusText = event.message;
      notifyListeners();
    } else if (event is LanFavSyncDone) {
      _markDone();
    } else if (event is LanFavSyncFatalError) {
      _markDone();
    }
  }

  // ── Minimize / unminimize ──────────────────────────────────────────────────

  void minimize() {
    _minimized = true;
    notifyListeners();
  }

  void unminimize() {
    _minimized = false;
    notifyListeners();
  }

  // ── Called by screens on minimize to hand off session / sub ownership ──────

  void takeReceiveSession(LanFavSyncReceiverSession session) {
    _receiverSession = session;
    receiveQrJson = session.qrJson;
  }

  void takeSendSub(StreamSubscription<LanFavSyncEvent> sub) {
    _sendSub = sub;
  }

  void takeSenderHandshakeSession(LanFavSyncSenderHandshakeSession session) {
    _senderHandshakeSession = session;
  }

  // ── Done ───────────────────────────────────────────────────────────────────

  void _markDone() {
    _phase = NearLinkBubblePhase.done;
    notifyListeners();
    if (_minimized) {
      Future.delayed(const Duration(seconds: 2), reset);
    }
  }

  void markDone() => _markDone();

  // ── Cancel (abort transfer from UI) ───────────────────────────────────────

  void cancelTransfer() {
    _sendSub?.cancel();
    _sendSub = null;
    _senderHandshakeSession?.close();
    _senderHandshakeSession = null;
    _receiverSession?.close();
    _receiverSession = null;
    _phase = NearLinkBubblePhase.idle;
    _minimized = false;
    current = 0;
    total = 0;
    statusText = '';
    isSend = false;
    receiveQrJson = null;
    notifyListeners();
  }

  // ── Reset / dismiss ────────────────────────────────────────────────────────

  void reset() {
    _sendSub?.cancel();
    _sendSub = null;
    _senderHandshakeSession?.close();
    _senderHandshakeSession = null;
    _phase = NearLinkBubblePhase.idle;
    _minimized = false;
    current = 0;
    total = 0;
    statusText = '';
    isSend = false;
    receiveQrJson = null;
    _receiverSession?.close();
    _receiverSession = null;
    notifyListeners();
  }
}

final nearLinkBubbleController = NearLinkBubbleController();

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/net.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../widgets/cards.dart';

/// Player a schermo intero.
///
/// - Diretta: ▲▼ cambiano canale (con un attimo di attesa, così lo zapping
///   veloce non apre ogni canale intermedio), OK mostra le informazioni.
/// - Film ed episodi: OK pausa, ◀▶ indietro/avanti (tenendo premuto accelera),
///   la posizione si salva da sola e l'episodio successivo parte da solo.
/// - Se il flusso cade, si riconnette da solo (1, 2, 4, 8 secondi).
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.items, required this.initialIndex, this.resumeAt});

  final List<PlaybackItem> items;
  final int initialIndex;
  final Duration? resumeAt;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const List<Duration> _retryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ];

  late final AppController _app;
  VideoPlayerController? _controller;
  late int _index;
  Duration? _pendingSeek;
  String? _error;
  String? _status;
  bool _overlay = true;
  bool _completed = false;
  int _attempt = 0;
  int _openToken = 0;
  List<EpgEntry> _epg = const <EpgEntry>[];

  Duration? _seekTarget;
  int _seekRepeats = 0;

  Timer? _overlayTimer;
  Timer? _retryTimer;
  Timer? _stallTimer;
  Timer? _healthyTimer;
  Timer? _saveTimer;
  Timer? _zapTimer;
  Timer? _seekTimer;

  PlaybackItem get _item => widget.items[_index];

  @override
  void initState() {
    super.initState();
    _app = AppScope.of(context);
    final start = widget.initialIndex;
    _index = (start < 0 || start >= widget.items.length) ? 0 : start;
    _pendingSeek = widget.resumeAt;
    WakelockPlus.enable();
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress(notify: false));
    _scheduleOverlayHide();
    _open();
  }

  @override
  void dispose() {
    // Salviamo dopo la chiusura della schermata: durante il dispose
    // non si possono aggiornare altre parti dell'interfaccia.
    final controller = _controller;
    final item = _item;
    if (controller != null && !item.isLive && controller.value.isInitialized) {
      final position = controller.value.position;
      final duration = controller.value.duration;
      final app = _app;
      Timer.run(() => app.saveProgress(item, position, duration));
    }
    for (final timer in [_overlayTimer, _retryTimer, _stallTimer, _healthyTimer, _saveTimer, _zapTimer, _seekTimer]) {
      timer?.cancel();
    }
    _controller = null;
    if (controller != null) {
      controller.removeListener(_onPlayerValue);
      controller.dispose();
    }
    WakelockPlus.disable();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Apertura e riconnessione

  Future<void> _open() async {
    final token = ++_openToken;
    _retryTimer?.cancel();
    _stallTimer?.cancel();
    _stallTimer = null;
    _healthyTimer?.cancel();
    _completed = false;

    final old = _controller;
    if (old != null) {
      old.removeListener(_onPlayerValue);
      _controller = null;
      // Il vecchio player si chiude dopo che è sparito dallo schermo.
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    if (_error != null || old != null) {
      setState(() => _error = null);
    }
    if (_item.isLive) _loadEpg();

    final url = _item.url;
    if (url.isEmpty) {
      setState(() => _error = 'Indirizzo del contenuto mancante');
      return;
    }

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      formatHint: url.toLowerCase().contains('.m3u8') ? VideoFormat.hls : null,
      httpHeaders: const {'User-Agent': kUserAgent},
    );
    try {
      await controller.initialize().timeout(const Duration(seconds: 25));
      if (!mounted || token != _openToken) {
        await controller.dispose();
        return;
      }
      final seek = _pendingSeek;
      _pendingSeek = null;
      if (seek != null && !_item.isLive && seek > Duration.zero) {
        await controller.seekTo(seek);
      }
      controller.addListener(_onPlayerValue);
      await controller.play();
      if (!mounted || token != _openToken) {
        controller.removeListener(_onPlayerValue);
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _status = null;
      });
      // Dopo 15 secondi di riproduzione regolare azzeriamo i tentativi.
      _healthyTimer = Timer(const Duration(seconds: 15), () => _attempt = 0);
    } on Object {
      await controller.dispose();
      if (!mounted || token != _openToken) return;
      _scheduleReconnect();
    }
  }

  void _onPlayerValue() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    if (value.hasError) {
      _scheduleReconnect();
      return;
    }
    // Buffering troppo lungo: il flusso è probabilmente bloccato.
    if (value.isBuffering) {
      _stallTimer ??= Timer(const Duration(seconds: 12), _scheduleReconnect);
    } else {
      _stallTimer?.cancel();
      _stallTimer = null;
    }
    if (!_item.isLive &&
        !_completed &&
        value.isInitialized &&
        value.duration > Duration.zero &&
        !value.isPlaying &&
        value.position >= value.duration - const Duration(milliseconds: 800)) {
      _completed = true;
      _onCompleted(value.duration);
    }
  }

  void _scheduleReconnect() {
    if (!mounted || (_retryTimer?.isActive ?? false)) return;
    _stallTimer?.cancel();
    _stallTimer = null;
    _healthyTimer?.cancel();
    final controller = _controller;
    if (controller != null && !_item.isLive) {
      final position = controller.value.position;
      if (position > Duration.zero) _pendingSeek = position;
    }
    if (_attempt >= _retryDelays.length) {
      setState(() {
        _status = null;
        _error = 'Impossibile riprodurre questo contenuto';
      });
      return;
    }
    final delay = _retryDelays[_attempt];
    _attempt++;
    setState(() => _status = 'Connessione persa, riprovo…');
    _retryTimer = Timer(delay, _open);
  }

  void _retryNow() {
    _attempt = 0;
    setState(() {
      _error = null;
      _status = null;
    });
    _open();
  }

  void _onCompleted(Duration duration) {
    _app.saveProgress(_item, duration, duration); // finito: esce da "Continua a guardare"
    if (_index + 1 < widget.items.length) {
      setState(() => _index++);
      _pendingSeek = null;
      _attempt = 0;
      _showOverlay();
      _open();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _saveProgress({bool notify = true}) {
    final controller = _controller;
    if (controller == null || _item.isLive) return;
    final value = controller.value;
    if (!value.isInitialized || value.duration <= Duration.zero) return;
    _app.saveProgress(_item, value.position, value.duration, notify: notify);
  }

  Future<void> _loadEpg() async {
    final channel = _item.channel;
    if (channel == null || !_app.supportsEpg) {
      if (_epg.isNotEmpty) setState(() => _epg = const <EpgEntry>[]);
      return;
    }
    final index = _index;
    final list = await _app.epgFor(channel);
    if (mounted && index == _index) setState(() => _epg = list);
  }

  // ---------------------------------------------------------------------------
  // Comandi del telecomando

  void _zap(int delta) {
    final count = widget.items.length;
    if (count <= 1) return;
    _controller?.pause();
    setState(() {
      _index = (_index + delta + count) % count;
      _error = null;
      _status = null;
      _epg = const <EpgEntry>[];
    });
    _showOverlay();
    _zapTimer?.cancel();
    _zapTimer = Timer(const Duration(milliseconds: 350), () {
      _attempt = 0;
      _pendingSeek = null;
      _open();
    });
  }

  void _seekBy(int direction, bool repeat) {
    final controller = _controller;
    if (controller == null || _item.isLive || !controller.value.isInitialized) return;
    _seekRepeats = repeat ? _seekRepeats + 1 : 0;
    final step = _seekRepeats > 12 ? 60 : (_seekRepeats > 4 ? 30 : 10);
    final base = _seekTarget ?? controller.value.position;
    var target = base + Duration(seconds: step * direction);
    final duration = controller.value.duration;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration - const Duration(seconds: 1);
    setState(() => _seekTarget = target);
    _showOverlay();
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 650), () async {
      final destination = _seekTarget;
      if (destination == null) return;
      await controller.seekTo(destination);
      if (mounted) setState(() => _seekTarget = null);
    });
  }

  void _togglePause() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      controller.pause();
      _saveProgress();
    } else {
      controller.play();
    }
    _showOverlay();
  }

  void _showOverlay() {
    if (!_overlay) setState(() => _overlay = true);
    _scheduleOverlayHide();
  }

  void _scheduleOverlayHide() {
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _overlay = false);
    });
  }

  void _toggleOverlay() {
    if (_overlay) {
      _overlayTimer?.cancel();
      setState(() => _overlay = false);
    } else {
      _showOverlay();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final isDown = event is KeyDownEvent;
    final isRepeat = event is KeyRepeatEvent;
    if (!isDown && !isRepeat) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isOk = key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter;

    if (_error != null && isOk) {
      if (isDown) _retryNow();
      return KeyEventResult.handled;
    }

    if (_item.isLive) {
      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.channelUp) {
        if (isDown) _zap(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.channelDown) {
        if (isDown) _zap(1);
        return KeyEventResult.handled;
      }
      if (isOk) {
        if (isDown) _toggleOverlay();
        return KeyEventResult.handled;
      }
    } else {
      if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.mediaRewind) {
        _seekBy(-1, isRepeat);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.mediaFastForward) {
        _seekBy(1, isRepeat);
        return KeyEventResult.handled;
      }
      if (isOk) {
        if (isDown) _togglePause();
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.mediaPlayPause || key == LogicalKeyboardKey.space) {
      if (isDown) _togglePause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.contextMenu) {
      if (isDown) _showOverlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored; // "Indietro" lo gestisce il sistema
  }

  // ---------------------------------------------------------------------------
  // Interfaccia

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final error = _error;
    final status = _status;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null)
              Center(
                child: AspectRatio(
                  aspectRatio: _aspectRatio(controller),
                  child: VideoPlayer(controller),
                ),
              ),
            if (controller != null)
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (context, value, child) {
                  if (error != null) return const SizedBox.shrink();
                  if (value.isBuffering) return const Center(child: CircularProgressIndicator());
                  if (!_item.isLive && value.isInitialized && !value.isPlaying && _seekTarget == null) {
                    return const Center(
                      child: Icon(Icons.pause_circle_filled_rounded, size: 84, color: Color(0xCCFFFFFF)),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            if (controller == null && error == null) const Center(child: CircularProgressIndicator()),
            if (status != null && error == null)
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: const Color(0xCC000000), borderRadius: BorderRadius.circular(20)),
                    child: Text(status, style: AppText.meta),
                  ),
                ),
              ),
            if (error != null) _ErrorMessage(message: error, isLive: _item.isLive),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _overlay || _seekTarget != null ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: _buildOverlay(controller),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _aspectRatio(VideoPlayerController controller) {
    final ratio = controller.value.aspectRatio;
    return ratio.isFinite && ratio > 0 ? ratio : 16 / 9;
  }

  Widget _buildOverlay(VideoPlayerController? controller) {
    final item = _item;
    final subtitle = item.subtitle;
    return Stack(
      fit: StackFit.expand,
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(48, 28, 48, 48),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xCC000000), Color(0x00000000)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title),
                if (subtitle != null)
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(48, 56, 48, 28),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xE6000000), Color(0x00000000)],
              ),
            ),
            child: item.isLive
                ? _liveBar()
                : (controller == null ? const SizedBox.shrink() : _vodBar(controller)),
          ),
        ),
      ],
    );
  }

  Widget _liveBar() {
    final now = DateTime.now();
    final (current, next) = currentAndNext(_epg, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (current != null) ...[
          Row(
            children: [
              const TagLabel('ORA'),
              const SizedBox(width: 8),
              Expanded(
                child: Text(current.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle),
              ),
              Text(_timeRange(current), style: AppText.meta),
            ],
          ),
          const SizedBox(height: 6),
          ProgressBar(value: current.progress(now)),
        ],
        if (next != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const TagLabel('DOPO'),
              const SizedBox(width: 8),
              Expanded(
                child: Text(next.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body),
              ),
              Text(_timeRange(next), style: AppText.meta),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Text(
          '${_index + 1} / ${widget.items.length}   ·   ▲▼ cambia canale   ·   OK informazioni',
          style: AppText.small,
        ),
      ],
    );
  }

  String _timeRange(EpgEntry entry) {
    final start = entry.start;
    final end = entry.end;
    if (start == null) return '';
    return end == null ? formatClock(start) : '${formatClock(start)} – ${formatClock(end)}';
  }

  Widget _vodBar(VideoPlayerController controller) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final duration = value.duration;
        final position = _seekTarget ?? value.position;
        final fraction = duration.inMilliseconds <= 0 ? 0.0 : position.inMilliseconds / duration.inMilliseconds;
        final hints = widget.items.length > 1
            ? 'OK pausa   ·   ◀▶ indietro/avanti   ·   ${_index + 1} di ${widget.items.length}'
            : 'OK pausa   ·   ◀▶ indietro/avanti';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ProgressBar(value: fraction, height: 4),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(formatDuration(position), style: _seekTarget != null ? AppText.title : AppText.meta),
                const Spacer(),
                Text(formatDuration(duration), style: AppText.meta),
              ],
            ),
            const SizedBox(height: 6),
            Text(hints, style: AppText.small),
          ],
        );
      },
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message, required this.isLive});

  final String message;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 52, color: Color(0xFFFF6B6B)),
          const SizedBox(height: 12),
          Text(message, style: AppText.title),
          const SizedBox(height: 8),
          Text(
            isLive ? 'OK per riprovare   ·   ▲▼ altro canale   ·   Indietro per uscire' : 'OK per riprovare   ·   Indietro per uscire',
            style: AppText.meta,
          ),
        ],
      ),
    );
  }
}

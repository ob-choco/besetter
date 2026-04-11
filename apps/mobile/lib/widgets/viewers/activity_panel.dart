import 'dart:async';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../services/activity_service.dart';
import 'slide_to_start.dart';
import 'activity_timer_panel.dart';
import 'activity_confirmation.dart';

enum _PanelState { slider, timer, confirmation }

class ActivityPanel extends StatefulWidget {
  final String routeId;
  final ValueChanged<Map<String, dynamic>>? onActivityCreated;

  const ActivityPanel({
    required this.routeId,
    this.onActivityCreated,
    Key? key,
  }) : super(key: key);

  @override
  State<ActivityPanel> createState() => _ActivityPanelState();
}

class _ActivityPanelState extends State<ActivityPanel> {
  _PanelState _state = _PanelState.slider;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  bool _lastWasCompleted = false;
  Timer? _autoDismissTimer;

  late ConfettiController _confettiController;

  // GPS coordinates captured at slide time
  double _latitude = 0.0;
  double _longitude = 0.0;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  Future<void> _captureLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          return; // latitude/longitude stay 0.0
        }
      }
      if (permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      _latitude = position.latitude;
      _longitude = position.longitude;
    } catch (_) {
      // GPS failure is not blocking — locationVerified will be false
    }
  }

  void _onSlideComplete() {
    setState(() {
      _startedAt = DateTime.now();
      _state = _PanelState.timer;
    });
    // GPS 위치는 비동기로 백그라운드에서 캡처
    _captureLocation();
  }

  void _onReset() {
    setState(() {
      _startedAt = DateTime.now();
    });
  }

  Future<void> _onFinish(bool completed) async {
    final endedAt = DateTime.now();
    final elapsed = endedAt.difference(_startedAt!);

    final status = completed ? 'completed' : 'attempted';

    try {
      final timezone = await FlutterTimezone.getLocalTimezone();

      final activityData = await ActivityService.createActivity(
        routeId: widget.routeId,
        status: status,
        startedAt: _startedAt!,
        endedAt: endedAt,
        latitude: _latitude,
        longitude: _longitude,
        timezone: timezone,
      );

      if (!mounted) return;

      setState(() {
        _elapsed = elapsed;
        _lastWasCompleted = completed;
        _state = _PanelState.confirmation;
      });

      widget.onActivityCreated?.call(activityData);

      if (completed) {
        _confettiController.play();
      }

      // Auto-dismiss after 2 seconds
      _autoDismissTimer?.cancel();
      _autoDismissTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && _state == _PanelState.confirmation) {
          _dismiss();
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.activitySaveFailed),
        ),
      );
    }
  }

  void _dismiss() {
    _autoDismissTimer?.cancel();
    setState(() {
      _startedAt = null;
      _latitude = 0.0;
      _longitude = 0.0;
      _state = _PanelState.slider;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: _buildPanel(),
        ),
        // Confetti overlay
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            numberOfParticles: 20,
            maxBlastForce: 30,
            minBlastForce: 10,
            gravity: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildPanel() {
    switch (_state) {
      case _PanelState.slider:
        return SlideToStart(onSlideComplete: _onSlideComplete);
      case _PanelState.timer:
        return ActivityTimerPanel(
          startedAt: _startedAt!,
          onReset: _onReset,
          onAttempted: () => _onFinish(false),
          onCompleted: () => _onFinish(true),
        );
      case _PanelState.confirmation:
        return ActivityConfirmation(
          isCompleted: _lastWasCompleted,
          elapsed: _elapsed,
          onDismiss: _dismiss,
        );
    }
  }
}

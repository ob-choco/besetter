import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ActivityTimerPanel extends StatefulWidget {
  final DateTime startedAt;
  final VoidCallback onReset;
  final VoidCallback onAttempted;
  final VoidCallback onCompleted;

  const ActivityTimerPanel({
    required this.startedAt,
    required this.onReset,
    required this.onAttempted,
    required this.onCompleted,
    Key? key,
  }) : super(key: key);

  @override
  State<ActivityTimerPanel> createState() => _ActivityTimerPanelState();
}

class _ActivityTimerPanelState extends State<ActivityTimerPanel> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _updateElapsed();
    _timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      _updateElapsed();
    });
  }

  void _updateElapsed() {
    if (!mounted) return;
    setState(() {
      _elapsed = DateTime.now().difference(widget.startedAt);
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    final centiseconds = ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$minutes:$seconds.$centiseconds';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE6E8EA)),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.08),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(25, 33, 25, 25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Duration label
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4ADE80).withValues(alpha: 0.75),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                l10n.duration,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF595C5D),
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Timer display
          Text(
            _formatDuration(_elapsed),
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2C2F30),
              letterSpacing: -1.8,
            ),
          ),
          const SizedBox(height: 24),
          // Action buttons
          Row(
            children: [
              // Reset button
              Expanded(
                child: _ActionButton(
                  icon: Icons.refresh,
                  color: const Color(0xFF595C5D),
                  backgroundColor: const Color(0xFFE6E8EA),
                  onTap: widget.onReset,
                ),
              ),
              const SizedBox(width: 12),
              // Attempted button
              Expanded(
                child: _ActionButton(
                  icon: Icons.close,
                  color: const Color(0xFF595C5D),
                  backgroundColor: const Color(0xFFE6E8EA),
                  onTap: widget.onAttempted,
                ),
              ),
              const SizedBox(width: 12),
              // Completed button
              Expanded(
                flex: 2,
                child: _ActionButton(
                  icon: Icons.check_circle_outline,
                  label: l10n.completed,
                  color: Colors.white,
                  backgroundColor: const Color(0xFF0066FF),
                  onTap: widget.onCompleted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final Color color;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    this.label,
    required this.color,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: label != null
              ? const [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.05),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 17),
            if (label != null) ...[
              const SizedBox(width: 8),
              Text(
                label!,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

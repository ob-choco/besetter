import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ActivityConfirmation extends StatelessWidget {
  final bool isCompleted;
  final Duration elapsed;
  final VoidCallback onDismiss;

  const ActivityConfirmation({
    required this.isCompleted,
    required this.elapsed,
    required this.onDismiss,
    Key? key,
  }) : super(key: key);

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    if (minutes > 0) {
      return '$minutes분 $seconds초';
    }
    return '$seconds초';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final statusText = isCompleted ? l10n.activityCompleted : l10n.activityAttempted;
    // TODO: 추후 첫 완등이면 "Flash!" / "Onsight!", 이후 완등이면 "Sent!" / "Crushed it!" / "Allez!" 등 랜덤
    final titleText = isCompleted ? l10n.activitySent : l10n.activityRecorded;

    return Container(
      decoration: BoxDecoration(
        color: isCompleted ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
        border: Border.all(
          color: isCompleted ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isCompleted ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCompleted ? Icons.check : Icons.close,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          // Title
          Text(
            titleText,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isCompleted ? const Color(0xFF166534) : const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 4),
          // Duration
          Text(
            l10n.activityDurationFormat(statusText, _formatDuration(elapsed)),
            style: TextStyle(
              fontSize: 13,
              color: isCompleted ? const Color(0xFF16A34A) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 16),
          // OK button
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onDismiss,
              style: TextButton.styleFrom(
                backgroundColor: isCompleted
                    ? const Color(0xFF22C55E).withValues(alpha: 0.1)
                    : const Color(0xFFE2E8F0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                l10n.ok,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isCompleted ? const Color(0xFF166534) : const Color(0xFF475569),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

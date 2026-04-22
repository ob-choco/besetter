import 'package:flutter/material.dart';

/// Unified section header used across the route viewer body.
///
/// Renders `[blue small-caps title]` on the left and an optional gray meta
/// string on the right. Optional `trailing` widget replaces `meta` when
/// provided (e.g., a tappable filter toggle).
class SectionHeader extends StatelessWidget {
  final String title;
  final String? meta;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.meta,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final rightSide = trailing ??
        (meta != null
            ? Text(
                meta!,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF6B7280),
                  letterSpacing: 0.5,
                ),
              )
            : const SizedBox.shrink());

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0052D0),
                letterSpacing: 1.5,
              ),
            ),
          ),
          rightSide,
        ],
      ),
    );
  }
}

/// 1px divider placed between body sections of the route viewer.
/// Inset 24px on each side to match the horizontal padding of sections.
class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      color: const Color(0xFFECEFF2),
    );
  }
}

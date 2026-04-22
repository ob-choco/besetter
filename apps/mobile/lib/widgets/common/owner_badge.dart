import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../models/route_data.dart';

class OwnerBadge extends StatelessWidget {
  final OwnerInfo owner;
  final double avatarSize;

  const OwnerBadge({
    super.key,
    required this.owner,
    this.avatarSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textStyle = TextStyle(
      fontSize: 12,
      color: Colors.grey[600],
    );

    if (owner.isDeleted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_off_outlined,
              size: avatarSize * 0.6,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(width: 6),
          Text(l10n.deletedUser, style: textStyle),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipOval(
          child: SizedBox(
            width: avatarSize,
            height: avatarSize,
            child: owner.profileImageUrl != null
                ? CachedNetworkImage(
                    imageUrl: owner.profileImageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _initialAvatar(),
                    errorWidget: (_, __, ___) => _initialAvatar(),
                  )
                : _initialAvatar(),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            owner.profileId ?? '',
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _initialAvatar() {
    final initial = (owner.profileId ?? '?').substring(0, 1).toUpperCase();
    return Container(
      color: const Color(0xFFE6ECFB),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFF1E4BD8),
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

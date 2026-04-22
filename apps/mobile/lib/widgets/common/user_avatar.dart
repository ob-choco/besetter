import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/route_data.dart';
import '../../utils/thumbnail_url.dart';

class UserAvatar extends StatelessWidget {
  final OwnerInfo owner;
  final double size;

  const UserAvatar({super.key, required this.owner, this.size = 40});

  @override
  Widget build(BuildContext context) {
    if (owner.isDeleted) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.person_off_outlined,
          size: size * 0.6,
          color: Colors.grey[500],
        ),
      );
    }

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: owner.profileImageUrl != null
            ? CachedNetworkImage(
                imageUrl: toThumbnailUrl(owner.profileImageUrl!, 's100'),
                fit: BoxFit.cover,
                placeholder: (_, __) => _initial(),
                errorWidget: (_, __, ___) => _initial(),
              )
            : _initial(),
      ),
    );
  }

  Widget _initial() {
    final initial = (owner.profileId ?? '?').substring(0, 1).toUpperCase();
    return Container(
      color: const Color(0xFFE6ECFB),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: const Color(0xFF1E4BD8),
          fontWeight: FontWeight.w700,
          fontSize: size * 0.35,
        ),
      ),
    );
  }
}

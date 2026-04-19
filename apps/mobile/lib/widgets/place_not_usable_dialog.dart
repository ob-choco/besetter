import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

Future<void> showPlaceNotUsableDialog(
  BuildContext context, {
  required String placeName,
}) {
  final l10n = AppLocalizations.of(context)!;
  final message = placeName.isEmpty
      ? l10n.placeNotUsableAny
      : l10n.placeNotUsableNamed(placeName);
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l10n.confirm),
        ),
      ],
    ),
  );
}

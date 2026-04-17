import 'package:flutter/material.dart';

Future<void> showPlaceNotUsableDialog(
  BuildContext context, {
  required String placeName,
}) {
  final message = placeName.isEmpty
      ? '이 장소는 쓸 수 없는 상태입니다.\n다른 장소를 선택해주세요.'
      : '해당 $placeName는 쓸 수 없는 상태입니다.\n다른 장소를 선택해주세요.';
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

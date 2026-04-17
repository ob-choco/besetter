import 'package:flutter/material.dart';

Future<void> showPlaceNotUsableDialog(
  BuildContext context, {
  required String placeName,
}) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(
        '해당 $placeName는 쓸 수 없는 상태입니다.\n다른 장소를 선택해주세요.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

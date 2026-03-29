import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:ui' as ui; // Flutter UI 패키지
import 'package:device_info_plus/device_info_plus.dart';
import '../pages/image_preview_page.dart';
import '../pages/image_picker_page.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class HoldEditorButton extends StatefulWidget {
  final GlobalKey buttonKey;
  final Function()? onTapDown;
  final String? buttonLabel;
  final IconData? buttonIcon;

  const HoldEditorButton({
    super.key,
    required this.buttonKey,
    this.onTapDown,
    this.buttonLabel,
    this.buttonIcon,
  });

  @override
  State<HoldEditorButton> createState() => _HoldEditorButtonState();
}

class _HoldEditorButtonState extends State<HoldEditorButton> {
  Future<void> _handleSourceSelected(BuildContext context, String source) async {
    // 가이드 풍선 제거는 홈 페이지에서 처리
    if (widget.onTapDown != null) {
      widget.onTapDown!();
    }

    File? selectedImage;

    try {
      if (source == 'wall_select') {
        Navigator.pushNamed(context, '/images');
        return;
      }

      if (source == 'camera') {
        if (Platform.isIOS) {
          final deviceInfo = await DeviceInfoPlugin().iosInfo;
          if (!deviceInfo.isPhysicalDevice) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLocalizations.of(context)!.cameraNotAvailableInSimulator)),
              );
            }
            return;
          }
        }

        final ImagePicker picker = ImagePicker();
        final XFile? photo = await picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.rear,
          imageQuality: 95,
        );

        if (photo != null) {
          selectedImage = File(photo.path);
          final ui.Image image = await decodeImageFromList(await selectedImage.readAsBytes());

          // 이미지 최소 해상도 검사 (가로/세로 방향 모두 고려)
          if (image.width < 480 || image.height < 480) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLocalizations.of(context)!.lowImageResolution)),
              );
            }
            return;
          }

          // 이미지 비율 검사 (1:1부터 16:9까지 허용)
          double ratio = image.width > image.height ? image.width / image.height : image.height / image.width;

          if (ratio < 1.0 || ratio > 1.78) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLocalizations.of(context)!.unsupportedImageRatio)),
              );
            }
            return;
          }
        }
      } else {
        final result = await Navigator.push<List<File>>(
          context,
          MaterialPageRoute(
            builder: (context) => ImagePickerPage(initialSelectedImages: const [], allowMultiple: false),
          ),
        );

        if (result != null && result.isNotEmpty) {
          selectedImage = result.first;
          final image = await decodeImageFromList(await selectedImage.readAsBytes());

          // 이미지 최소 해상도 검사 (가로/세로 방향 모두 고려)
          if (image.width < 480 || image.height < 480) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLocalizations.of(context)!.lowImageResolution)),
              );
            }
            return;
          }

          // 이미지 비율 검사 (1:1부터 16:9까지 허용)
          double ratio = image.width > image.height ? image.width / image.height : image.height / image.width;

          if (ratio < 1.0 || ratio > 1.78) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLocalizations.of(context)!.unsupportedImageRatio)),
              );
            }
            return;
          }

          final int longSide = image.width > image.height ? image.width : image.height;
          final int shortSide = image.width < image.height ? image.width : image.height;

          if (longSide > 4928 || shortSide > 3264) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLocalizations.of(context)!.imageResolutionLimited)),
              );
            }
            return;
          }
        }
      }

      if (selectedImage != null && context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImagePreviewPage(
              image: selectedImage!,
              source: source,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.errorSelectingImage)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: widget.buttonKey,
      onTapDown: (TapDownDetails details) async {
        // 상위 위젯에 탭 이벤트 알림
        if (widget.onTapDown != null) {
          widget.onTapDown!();
        }

        final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
        final RelativeRect position = RelativeRect.fromRect(
          Rect.fromPoints(
            details.globalPosition,
            details.globalPosition,
          ),
          Offset.zero & overlay.size,
        );

        showMenu<String>(
          context: context,
          position: position,
          items: <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'camera',
              child: Row(
                children: [
                  Icon(Icons.camera_alt),
                  SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.takePhoto),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'gallery',
              child: Row(
                children: [
                  Icon(Icons.photo_library),
                  SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.selectPhoto),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'wall_select',
              child: Row(
                children: [
                  Icon(Icons.landscape),
                  SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.selectWall),
                ],
              ),
            ),
          ],
        ).then((String? value) {
          if (value != null) {
            _handleSourceSelected(context, value);
          }
        });
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF007AFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.buttonIcon != null) ...[
              Icon(widget.buttonIcon, color: Colors.white, size: 24),
              const SizedBox(width: 8),
            ],
            Text(
              widget.buttonLabel ?? AppLocalizations.of(context)!.setRoute,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

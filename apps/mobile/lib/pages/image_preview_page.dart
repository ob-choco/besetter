import 'package:flutter/material.dart';
import 'dart:io';
import '../models/polygon_data.dart';
import 'editors/spray_wall_editor_page.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/images_provider.dart';

class ImagePreviewPage extends ConsumerWidget {
  final File image;
  final String source;

  const ImagePreviewPage({
    super.key,
    required this.image,
    required this.source,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.checkImage),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Image.file(image),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(32.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                InkWell(
                  onTap: () {
                    Navigator.pop(context, false);
                  },
                  child: SvgPicture.asset(
                    'assets/icons/retry_button.svg',
                    width: 64,
                    height: 64,
                  ),
                ),
                InkWell(
                  onTap: () async {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => AlertDialog(
                        backgroundColor: Colors.black54,
                        contentPadding: const EdgeInsets.all(16),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              AppLocalizations.of(context)!.recognizingHolds,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );

                    try {
                      final PolygonData? polygonData = await ref.read(imagesProvider.notifier).createImage(image);

                      if (context.mounted) {
                        Navigator.pop(context);
                      }

                      if (polygonData != null) {
                        if (context.mounted) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SprayWallEditorPage(
                                imageFile: image,
                                polygonData: polygonData,
                              ),
                            ),
                          );
                        }
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(AppLocalizations.of(context)!.holdRecognitionError)),
                          );
                        }
                      }
                    } catch (e) {
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(AppLocalizations.of(context)!.holdRecognitionError)),
                        );
                      }
                    }
                  },
                  child: SvgPicture.asset(
                    'assets/icons/scan_button.svg',
                    width: 64,
                    height: 64,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

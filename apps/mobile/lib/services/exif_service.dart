import 'dart:io';
import 'package:exif/exif.dart';

class GpsCoordinates {
  final double latitude;
  final double longitude;

  GpsCoordinates({required this.latitude, required this.longitude});
}

class ExifService {
  static Future<GpsCoordinates?> extractGpsFromFile(File file) async {
    final bytes = await file.readAsBytes();
    final data = await readExifFromBytes(bytes);

    if (data.isEmpty) return null;

    final latTag = data['GPS GPSLatitude'];
    final latRefTag = data['GPS GPSLatitudeRef'];
    final lonTag = data['GPS GPSLongitude'];
    final lonRefTag = data['GPS GPSLongitudeRef'];

    if (latTag == null || latRefTag == null || lonTag == null || lonRefTag == null) {
      return null;
    }

    final latRatios = latTag.values.toList();
    final lonRatios = lonTag.values.toList();

    if (latRatios.length < 3 || lonRatios.length < 3) return null;

    double dmsToDecimal(List ratios) {
      double degrees = ratios[0].numerator / ratios[0].denominator;
      double minutes = ratios[1].numerator / ratios[1].denominator;
      double seconds = ratios[2].numerator / ratios[2].denominator;
      return degrees + (minutes / 60) + (seconds / 3600);
    }

    double latitude = dmsToDecimal(latRatios);
    double longitude = dmsToDecimal(lonRatios);

    final latRef = latRefTag.printable;
    final lonRef = lonRefTag.printable;

    if (latRef == 'S') latitude = -latitude;
    if (lonRef == 'W') longitude = -longitude;

    if (latitude == 0.0 && longitude == 0.0) return null;

    return GpsCoordinates(latitude: latitude, longitude: longitude);
  }
}

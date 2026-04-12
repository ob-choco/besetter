import '../services/http_client.dart';

/// Converts a GCS image URL to a thumbnail URL via our API endpoint.
///
/// The API endpoint generates thumbnails on-demand and redirects to the cached version.
/// Presets: 'w400' (width 400px), 's100' (100x100 square crop)
String toThumbnailUrl(String imageUrl, String preset) {
  final uri = Uri.parse(imageUrl);
  final segments = uri.pathSegments;
  if (segments.length < 2) return imageUrl;
  // Skip bucket name (first segment), join the rest as blob path
  final blobPath = segments.sublist(1).join('/');
  return '${AuthorizedHttpClient.baseUrl}/images/$blobPath?type=$preset';
}

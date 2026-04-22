import 'dart:convert';

import '../models/verified_completer.dart';
import 'http_client.dart';

class VerifiedCompletersService {
  static Future<VerifiedCompletersPage> fetch({
    required String routeId,
    int limit = 20,
    String? cursor,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      if (cursor != null) 'cursor': cursor,
    };
    final path = Uri.parse('/routes/$routeId/verified-completers')
        .replace(queryParameters: query)
        .toString();

    final response = await AuthorizedHttpClient.get(path);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load verified completers: ${response.statusCode}',
      );
    }
    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final items = (decoded['data'] as List<dynamic>)
        .map((e) => VerifiedCompleter.fromJson(e as Map<String, dynamic>))
        .toList();
    final meta = decoded['meta'] as Map<String, dynamic>? ?? const {};
    final nextToken = meta['nextToken'] as String?;
    return VerifiedCompletersPage(items: items, nextToken: nextToken);
  }
}

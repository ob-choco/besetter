import 'dart:convert';
import 'dart:io';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../services/http_client.dart';

part 'user_provider.g.dart';

class ProfileIdAvailability {
  final String value;
  final bool available;
  final String? reason;

  const ProfileIdAvailability({
    required this.value,
    required this.available,
    this.reason,
  });

  factory ProfileIdAvailability.fromJson(Map<String, dynamic> json) {
    return ProfileIdAvailability(
      value: json['value'] as String,
      available: json['available'] as bool,
      reason: json['reason'] as String?,
    );
  }
}

class ProfileIdUpdateError implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const ProfileIdUpdateError({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  @override
  String toString() => 'ProfileIdUpdateError($statusCode, $code): $message';
}

class UserState {
  final String id;
  final String profileId;
  final String? name;
  final String? email;
  final String? bio;
  final String? profileImageUrl;
  final int unreadNotificationCount;

  const UserState({
    required this.id,
    required this.profileId,
    this.name,
    this.email,
    this.bio,
    this.profileImageUrl,
    this.unreadNotificationCount = 0,
  });

  UserState copyWith({
    String? id,
    String? profileId,
    String? name,
    String? email,
    String? bio,
    String? profileImageUrl,
    int? unreadNotificationCount,
  }) {
    return UserState(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      name: name ?? this.name,
      email: email ?? this.email,
      bio: bio ?? this.bio,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      unreadNotificationCount:
          unreadNotificationCount ?? this.unreadNotificationCount,
    );
  }

  factory UserState.fromJson(Map<String, dynamic> json) {
    return UserState(
      id: json['id'] as String,
      profileId: json['profileId'] as String,
      name: json['name'] as String?,
      email: json['email'] as String?,
      bio: json['bio'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
      unreadNotificationCount:
          (json['unreadNotificationCount'] as int?) ?? 0,
    );
  }
}

@Riverpod(keepAlive: true)
class UserProfile extends _$UserProfile {
  @override
  Future<UserState> build() async {
    return _fetchProfile();
  }

  Future<UserState> _fetchProfile() async {
    final response = await AuthorizedHttpClient.get('/users/me');
    if (response.statusCode == 200) {
      return UserState.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
    }
    throw Exception('Failed to load profile');
  }

  Future<void> updateProfile({
    String? name,
    String? bio,
    File? imageFile,
  }) async {
    final fields = <String, String>{};
    if (name != null) fields['name'] = name;
    if (bio != null) fields['bio'] = bio;

    final response = await AuthorizedHttpClient.multipartRequest(
      '/users/me',
      imageFile?.path,
      fieldName: 'profileImage',
      fields: fields,
      method: 'PATCH',
    );

    if (response.statusCode == 200) {
      state = AsyncData(
        UserState.fromJson(jsonDecode(utf8.decode(response.bodyBytes))),
      );
    } else {
      throw Exception('Failed to update profile');
    }
  }

  Future<ProfileIdAvailability> checkProfileIdAvailability(String value) async {
    final encoded = Uri.encodeQueryComponent(value);
    final response = await AuthorizedHttpClient.get(
      '/users/me/profile-id/availability?value=$encoded',
    );
    if (response.statusCode == 200) {
      return ProfileIdAvailability.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
    }
    throw Exception('Failed to check profile_id availability');
  }

  Future<void> updateProfileId(String value) async {
    final response = await AuthorizedHttpClient.patch(
      '/users/me/profile-id',
      body: {'profileId': value},
    );
    if (response.statusCode == 200) {
      state = AsyncData(
        UserState.fromJson(jsonDecode(utf8.decode(response.bodyBytes))),
      );
      return;
    }
    try {
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final detail = body['detail'];
      if (detail is Map<String, dynamic>) {
        throw ProfileIdUpdateError(
          statusCode: response.statusCode,
          code: (detail['code'] as String?) ?? 'UNKNOWN',
          message: (detail['message'] as String?) ?? '',
        );
      }
    } catch (e) {
      if (e is ProfileIdUpdateError) rethrow;
    }
    throw ProfileIdUpdateError(
      statusCode: response.statusCode,
      code: 'UNKNOWN',
      message: 'Failed to update profile_id',
    );
  }
}

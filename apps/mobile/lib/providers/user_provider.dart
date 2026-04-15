import 'dart:convert';
import 'dart:io';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../services/http_client.dart';

part 'user_provider.g.dart';

class UserState {
  final String id;
  final String? name;
  final String? email;
  final String? bio;
  final String? profileImageUrl;
  final int unreadNotificationCount;

  const UserState({
    required this.id,
    this.name,
    this.email,
    this.bio,
    this.profileImageUrl,
    this.unreadNotificationCount = 0,
  });

  UserState copyWith({
    String? id,
    String? name,
    String? email,
    String? bio,
    String? profileImageUrl,
    int? unreadNotificationCount,
  }) {
    return UserState(
      id: id ?? this.id,
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
}

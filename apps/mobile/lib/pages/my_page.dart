import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../providers/user_provider.dart';
import 'setting.dart';

class MyPage extends HookConsumerWidget {
  const MyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider);
    final isEditing = useState(false);
    final croppedImage = useState<File?>(null);
    final nameController = useTextEditingController();
    final bioController = useTextEditingController();
    final isSaving = useState(false);
    final selectedDay = useState<int>(15);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F6F7),
        elevation: 0,
        centerTitle: true,
        title: Text(
          l10n.profile,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 24,
            color: Color(0xFF2C2F30),
          ),
        ),
        actions: [
          if (!isSaving.value)
            IconButton(
              icon: Icon(
                isEditing.value ? Icons.check : Icons.edit_outlined,
                color: const Color(0xFF2C2F30),
              ),
              onPressed: () async {
                if (isEditing.value) {
                  isSaving.value = true;
                  try {
                    await ref.read(userProfileProvider.notifier).updateProfile(
                      name: nameController.text,
                      bio: bioController.text,
                      imageFile: croppedImage.value,
                    );
                    isEditing.value = false;
                    croppedImage.value = null;
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.profileUpdated)),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.failedUpdateProfile)),
                      );
                    }
                  } finally {
                    isSaving.value = false;
                  }
                } else {
                  final user = userAsync.valueOrNull;
                  nameController.text = user?.name ?? '';
                  bioController.text = user?.bio ?? '';
                  isEditing.value = true;
                }
              },
            )
          else
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Color(0xFF2C2F30)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.failedLoadProfile),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => ref.invalidate(userProfileProvider),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
        data: (user) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            children: [
              const SizedBox(height: 16),
              _ProfileHeader(
                user: user,
                isEditing: isEditing.value,
                croppedImage: croppedImage,
                nameController: nameController,
                bioController: bioController,
              ),
              const SizedBox(height: 32),
              _MonthlyCalendar(selectedDay: selectedDay),
              const SizedBox(height: 32),
              _RecentWorkout(selectedDay: selectedDay.value),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final UserState user;
  final bool isEditing;
  final ValueNotifier<File?> croppedImage;
  final TextEditingController nameController;
  final TextEditingController bioController;

  const _ProfileHeader({
    required this.user,
    required this.isEditing,
    required this.croppedImage,
    required this.nameController,
    required this.bioController,
  });

  Future<void> _pickAndCropImage(BuildContext context) async {
    final editProfileLabel = AppLocalizations.of(context)!.editProfile;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: editProfileLabel,
          cropStyle: CropStyle.circle,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: editProfileLabel,
          cropStyle: CropStyle.circle,
          aspectRatioLockEnabled: true,
        ),
      ],
    );

    if (cropped != null) {
      croppedImage.value = File(cropped.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 프로필 이미지
        SizedBox(
          width: 96,
          height: 112,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x330066FF),
                  border: Border.all(
                    color: const Color(0xFFDADDDF),
                    width: 4,
                  ),
                ),
                child: ClipOval(
                  child: croppedImage.value != null
                      ? Image.file(croppedImage.value!, fit: BoxFit.cover)
                      : user.profileImageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: user.profileImageUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => const Icon(
                                Icons.person,
                                size: 40,
                                color: Color(0xFF595C5D),
                              ),
                              errorWidget: (_, __, ___) => const Icon(
                                Icons.person,
                                size: 40,
                                color: Color(0xFF595C5D),
                              ),
                            )
                          : const Icon(
                              Icons.person,
                              size: 40,
                              color: Color(0xFF595C5D),
                            ),
                ),
              ),
              if (isEditing)
                Positioned(
                  right: 0,
                  bottom: 16,
                  child: GestureDetector(
                    onTap: () => _pickAndCropImage(context),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0066FF),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // 이름
        if (isEditing)
          SizedBox(
            width: 200,
            child: TextField(
              controller: nameController,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 24,
                color: Color(0xFF2C2F30),
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
                border: UnderlineInputBorder(),
              ),
            ),
          )
        else
          Text(
            user.name ?? '',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 24,
              color: Color(0xFF2C2F30),
            ),
          ),
        const SizedBox(height: 4),
        // 자기소개
        if (isEditing)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: TextField(
              controller: bioController,
              textAlign: TextAlign.center,
              maxLines: 3,
              minLines: 1,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF595C5D),
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
                border: UnderlineInputBorder(),
              ),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              user.bio ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF595C5D),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Mock Data ───────────────────────────────────────────────

const _mockWorkoutDays = {1, 4, 5, 9, 11, 12, 13, 15, 17};

const _mockWorkouts = <int, Map<String, String>>{
  1: {'grade': 'V4', 'sector': 'The Slab', 'name': 'Morning Light', 'gym': 'Urban Apex Gym', 'color': '#4CAF50'},
  4: {'grade': 'V6', 'sector': 'Cave Wall', 'name': 'Shadow Play', 'gym': 'Urban Apex Gym', 'color': '#FF9800'},
  5: {'grade': 'V5', 'sector': 'Overhang', 'name': 'Iron Grip', 'gym': 'Urban Apex Gym', 'color': '#2196F3'},
  9: {'grade': 'V3', 'sector': 'Vertical', 'name': 'Steady Rise', 'gym': 'Boulder Lab', 'color': '#8BC34A'},
  11: {'grade': 'V5', 'sector': 'Roof', 'name': 'Ceiling Walk', 'gym': 'Boulder Lab', 'color': '#2196F3'},
  12: {'grade': 'V6', 'sector': 'Arete', 'name': 'Edge Runner', 'gym': 'Boulder Lab', 'color': '#FF9800'},
  13: {'grade': 'V4', 'sector': 'Slab Wall', 'name': 'Glass Step', 'gym': 'Boulder Lab', 'color': '#4CAF50'},
  15: {'grade': 'V7', 'sector': 'The Overhang', 'name': 'Electric Drift', 'gym': 'Urban Apex Gym', 'color': '#F5A9F2'},
  17: {'grade': 'V5', 'sector': 'Slab Wall', 'name': 'Crimson Flow', 'gym': 'Urban Apex Gym', 'color': '#E91E63'},
};

// ─── Monthly Calendar ────────────────────────────────────────

class _MonthlyCalendar extends StatelessWidget {
  final ValueNotifier<int> selectedDay;

  const _MonthlyCalendar({required this.selectedDay});

  @override
  Widget build(BuildContext context) {
    // October 2023 starts on Sunday (weekday index 0)
    const firstDayOfWeek = 0; // Sunday
    const daysInMonth = 31;
    const dayHeaders = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A2C2F30),
            blurRadius: 24,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 헤더
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppLocalizations.of(context)!.monthlyProgress,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Color(0xFF2C2F30),
                ),
              ),
              Row(
                children: const [
                  Text(
                    'October 2023',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Color(0xFF0066FF),
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    Icons.calendar_today,
                    size: 15,
                    color: Color(0xFF0066FF),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          // 요일 헤더
          Row(
            children: dayHeaders
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            color: Color(0x99595C5D),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          // 달력 그리드
          ...List.generate(5, (weekIndex) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: List.generate(7, (dayIndex) {
                  final dayNumber = weekIndex * 7 + dayIndex - firstDayOfWeek + 1;
                  if (dayNumber < 1 || dayNumber > daysInMonth) {
                    return const Expanded(child: SizedBox(height: 42));
                  }

                  final hasWorkout = _mockWorkoutDays.contains(dayNumber);
                  final isSelected = selectedDay.value == dayNumber;

                  return Expanded(
                    child: GestureDetector(
                      onTap: hasWorkout
                          ? () => selectedDay.value = dayNumber
                          : null,
                      child: Container(
                        height: 42,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: hasWorkout ? const Color(0x1A0066FF) : null,
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected
                              ? Border.all(color: const Color(0xFF0066FF), width: 2)
                              : null,
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Text(
                              '$dayNumber',
                              style: TextStyle(
                                fontWeight: hasWorkout ? FontWeight.w600 : FontWeight.w500,
                                fontSize: 14,
                                color: isSelected
                                    ? const Color(0xFF0066FF)
                                    : hasWorkout
                                        ? const Color(0xFF2C2F30)
                                        : const Color(0x80595C5D),
                              ),
                            ),
                            if (hasWorkout)
                              Positioned(
                                bottom: 4,
                                child: Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF0066FF),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Recent Workout Card ─────────────────────────────────────

class _RecentWorkout extends StatelessWidget {
  final int selectedDay;

  const _RecentWorkout({required this.selectedDay});

  @override
  Widget build(BuildContext context) {
    final workout = _mockWorkouts[selectedDay];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.recentWorkout,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Color(0xFF2C2F30),
          ),
        ),
        const SizedBox(height: 16),
        if (workout != null)
          _WorkoutCard(workout: workout)
        else
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'No workout on this day',
                style: TextStyle(color: Color(0xFF595C5D), fontSize: 14),
              ),
            ),
          ),
      ],
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  final Map<String, String> workout;

  const _WorkoutCard({required this.workout});

  @override
  Widget build(BuildContext context) {
    final gradeColor = Color(
      int.parse(workout['color']!.replaceFirst('#', ''), radix: 16) | 0xFF000000,
    );

    return Container(
      height: 256,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 32,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    gradeColor.withValues(alpha: 0.6),
                    gradeColor.withValues(alpha: 0.9),
                  ],
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Color(0xCC000000),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: gradeColor,
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Text(
                      '${workout['grade']} \u2022 ${workout['sector']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    workout['name']!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 30,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    workout['gym']!,
                    style: const TextStyle(
                      fontSize: 18,
                      color: Color(0xCCFFFFFF),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

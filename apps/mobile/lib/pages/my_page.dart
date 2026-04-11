import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../providers/user_provider.dart';
import '../services/activity_service.dart';
import '../utils/thumbnail_url.dart';
import 'setting.dart';

class MyPage extends HookConsumerWidget {
  final int refreshSignal;
  const MyPage({this.refreshSignal = 0, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider);
    final isEditing = useState(false);
    final croppedImage = useState<File?>(null);
    final nameController = useTextEditingController();
    final bioController = useTextEditingController();
    final isSaving = useState(false);
    final l10n = AppLocalizations.of(context)!;

    // Calendar state
    final now = DateTime.now();
    final calendarYear = useState(now.year);
    final calendarMonth = useState(now.month);
    final selectedDay = useState<int?>(null);
    final activeDates = useState<List<int>>([]);
    final dailyRoutesData = useState<Map<String, dynamic>?>(null);
    final calendarLoading = useState(true);
    final dailyRoutesLoading = useState(false);
    final timezone = useState<String>('Asia/Seoul');

    // Caches (persist across rebuilds)
    final monthlySummaryCache = useRef(<String, List<int>>{});
    final dailyRoutesCache = useRef(<String, Map<String, dynamic>>{});

    // Helper: is current month
    bool isCurrentMonth(int y, int m) => y == now.year && m == now.month;

    // Helper: is today
    bool isToday(int y, int m, int d) => y == now.year && m == now.month && d == now.day;

    // Load monthly summary
    Future<void> loadMonthlySummary(int year, int month, String tz) async {
      final cacheKey = '$year-${month.toString().padLeft(2, '0')}';
      if (!isCurrentMonth(year, month) && monthlySummaryCache.value.containsKey(cacheKey)) {
        activeDates.value = monthlySummaryCache.value[cacheKey]!;
        return;
      }
      try {
        final dates = await ActivityService.getMonthlySummary(year: year, month: month, timezone: tz);
        activeDates.value = dates;
        if (!isCurrentMonth(year, month)) {
          monthlySummaryCache.value[cacheKey] = dates;
        }
      } catch (_) {
        activeDates.value = [];
      }
    }

    // Load daily routes
    Future<void> loadDailyRoutes(int year, int month, int day, String tz) async {
      final dateStr = '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      if (!isToday(year, month, day) && dailyRoutesCache.value.containsKey(dateStr)) {
        dailyRoutesData.value = dailyRoutesCache.value[dateStr];
        return;
      }
      dailyRoutesLoading.value = true;
      try {
        final data = await ActivityService.getDailyRoutes(date: dateStr, timezone: tz);
        dailyRoutesData.value = data;
        if (!isToday(year, month, day)) {
          dailyRoutesCache.value[dateStr] = data;
        }
      } catch (_) {
        dailyRoutesData.value = null;
      } finally {
        dailyRoutesLoading.value = false;
      }
    }

    // Initial load
    useEffect(() {
      () async {
        final tz = await FlutterTimezone.getLocalTimezone();
        timezone.value = tz;
        final lastDate = await ActivityService.getLastActivityDate(timezone: tz);
        if (lastDate != null) {
          final parts = lastDate.split('-').map(int.parse).toList();
          calendarYear.value = parts[0];
          calendarMonth.value = parts[1];
          selectedDay.value = parts[2];
          await Future.wait([
            loadMonthlySummary(parts[0], parts[1], tz),
            loadDailyRoutes(parts[0], parts[1], parts[2], tz),
          ]);
        } else {
          await loadMonthlySummary(now.year, now.month, tz);
        }
        calendarLoading.value = false;
      }();
      return null;
    }, []);

    // Reload when signaled (tab entry after activity change)
    useEffect(() {
      if (refreshSignal == 0) return null;
      monthlySummaryCache.value.clear();
      dailyRoutesCache.value.clear();
      final tz = timezone.value;
      loadMonthlySummary(calendarYear.value, calendarMonth.value, tz);
      if (selectedDay.value != null) {
        loadDailyRoutes(calendarYear.value, calendarMonth.value, selectedDay.value!, tz);
      }
      return null;
    }, [refreshSignal]);

    // Month navigation
    void goToPrevMonth() {
      int newYear = calendarYear.value;
      int newMonth = calendarMonth.value - 1;
      if (newMonth < 1) { newMonth = 12; newYear--; }
      if (newYear < 2026 || (newYear == 2026 && newMonth < 4)) return;
      calendarYear.value = newYear;
      calendarMonth.value = newMonth;
      selectedDay.value = null;
      dailyRoutesData.value = null;
      loadMonthlySummary(newYear, newMonth, timezone.value);
    }

    void goToNextMonth() {
      int newYear = calendarYear.value;
      int newMonth = calendarMonth.value + 1;
      if (newMonth > 12) { newMonth = 1; newYear++; }
      if (newYear > now.year || (newYear == now.year && newMonth > now.month)) return;
      calendarYear.value = newYear;
      calendarMonth.value = newMonth;
      selectedDay.value = null;
      dailyRoutesData.value = null;
      loadMonthlySummary(newYear, newMonth, timezone.value);
    }

    void onDaySelected(int day) {
      selectedDay.value = day;
      loadDailyRoutes(calendarYear.value, calendarMonth.value, day, timezone.value);
    }

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
          if (isEditing.value && !isSaving.value)
            IconButton(
              icon: const Icon(Icons.close, color: Color(0xFF2C2F30)),
              onPressed: () {
                isEditing.value = false;
                croppedImage.value = null;
              },
            ),
          if (!isSaving.value)
            IconButton(
              icon: Icon(
                isEditing.value ? Icons.check : Icons.edit_outlined,
                color: isEditing.value ? const Color(0xFF0066FF) : const Color(0xFF2C2F30),
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
              if (calendarLoading.value)
                const Center(child: CircularProgressIndicator(strokeWidth: 2))
              else ...[
                _MonthlyCalendar(
                  year: calendarYear.value,
                  month: calendarMonth.value,
                  activeDates: activeDates.value,
                  selectedDay: selectedDay.value,
                  onDaySelected: onDaySelected,
                  onPrevMonth: goToPrevMonth,
                  onNextMonth: goToNextMonth,
                  canGoPrev: !(calendarYear.value == 2026 && calendarMonth.value == 4),
                  canGoNext: !isCurrentMonth(calendarYear.value, calendarMonth.value),
                ),
                const SizedBox(height: 32),
                _DailyRoutes(
                  data: dailyRoutesData.value,
                  loading: dailyRoutesLoading.value,
                  selectedDay: selectedDay.value,
                ),
              ],
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
                              imageUrl: toThumbnailUrl(user.profileImageUrl!, 's100'),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  child: Text(
                    AppLocalizations.of(context)!.labelName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF595C5D),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: nameController,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: Color(0xFF2C2F30),
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                      border: UnderlineInputBorder(),
                    ),
                  ),
                ),
              ],
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
        const SizedBox(height: 16),
        // 자기소개
        if (isEditing)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    AppLocalizations.of(context)!.labelBio,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF595C5D),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFDADDDF)),
                    ),
                    child: TextField(
                      controller: bioController,
                      maxLines: 4,
                      minLines: 3,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF595C5D),
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ],
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

// ─── Monthly Calendar ────────────────────────────────────────

class _MonthlyCalendar extends StatelessWidget {
  final int year;
  final int month;
  final List<int> activeDates;
  final int? selectedDay;
  final ValueChanged<int> onDaySelected;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final bool canGoPrev;
  final bool canGoNext;

  const _MonthlyCalendar({
    required this.year,
    required this.month,
    required this.activeDates,
    required this.selectedDay,
    required this.onDaySelected,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.canGoPrev,
    required this.canGoNext,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = l10n.localeName;

    final firstDayOfMonth = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = firstDayOfMonth.weekday % 7; // Sunday = 0
    final totalCells = firstWeekday + daysInMonth;
    final weeks = (totalCells / 7).ceil();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final monthLabel = '${_monthName(month, locale)} $year';
    const dayHeaders = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Color(0x0A2C2F30), blurRadius: 24, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.monthlyProgress, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF2C2F30))),
              Row(
                children: [
                  GestureDetector(
                    onTap: canGoPrev ? onPrevMonth : null,
                    child: Icon(Icons.chevron_left, size: 20, color: canGoPrev ? const Color(0xFF0066FF) : const Color(0xFFDADDDF)),
                  ),
                  const SizedBox(width: 4),
                  Text(monthLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF0066FF))),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: canGoNext ? onNextMonth : null,
                    child: Icon(Icons.chevron_right, size: 20, color: canGoNext ? const Color(0xFF0066FF) : const Color(0xFFDADDDF)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: dayHeaders.map((d) => Expanded(
              child: Center(child: Text(d, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Color(0x99595C5D), letterSpacing: 0.5))),
            )).toList(),
          ),
          const SizedBox(height: 8),
          ...List.generate(weeks, (weekIndex) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: List.generate(7, (dayIndex) {
                  final dayNumber = weekIndex * 7 + dayIndex - firstWeekday + 1;
                  if (dayNumber < 1 || dayNumber > daysInMonth) {
                    return const Expanded(child: SizedBox(height: 42));
                  }

                  final cellDate = DateTime(year, month, dayNumber);
                  final isFuture = cellDate.isAfter(today);
                  final hasWorkout = activeDates.contains(dayNumber);
                  final isSelected = selectedDay == dayNumber;
                  final canTap = hasWorkout && !isFuture;

                  return Expanded(
                    child: GestureDetector(
                      onTap: canTap ? () => onDaySelected(dayNumber) : null,
                      child: Container(
                        height: 42,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: hasWorkout && !isFuture ? const Color(0x1A0066FF) : null,
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected ? Border.all(color: const Color(0xFF0066FF), width: 2) : null,
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Text(
                              '$dayNumber',
                              style: TextStyle(
                                fontWeight: hasWorkout ? FontWeight.w600 : FontWeight.w500,
                                fontSize: 14,
                                color: isFuture
                                    ? const Color(0x40595C5D)
                                    : isSelected
                                        ? const Color(0xFF0066FF)
                                        : hasWorkout
                                            ? const Color(0xFF2C2F30)
                                            : const Color(0x80595C5D),
                              ),
                            ),
                            if (hasWorkout && !isFuture)
                              Positioned(
                                bottom: 4,
                                child: Container(width: 5, height: 5, decoration: const BoxDecoration(color: Color(0xFF0066FF), shape: BoxShape.circle)),
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

  static String _monthName(int month, String locale) {
    const en = ['', 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    const ko = ['', '1월', '2월', '3월', '4월', '5월', '6월', '7월', '8월', '9월', '10월', '11월', '12월'];
    const ja = ['', '1月', '2月', '3月', '4月', '5月', '6月', '7月', '8月', '9月', '10月', '11月', '12月'];
    const es = ['', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    if (locale.startsWith('ko')) return ko[month];
    if (locale.startsWith('ja')) return ja[month];
    if (locale.startsWith('es')) return es[month];
    return en[month];
  }
}

// ─── Daily Routes ─────────────────────────────────────────────

class _DailyRoutes extends StatelessWidget {
  final Map<String, dynamic>? data;
  final bool loading;
  final int? selectedDay;

  const _DailyRoutes({
    required this.data,
    required this.loading,
    required this.selectedDay,
  });

  String _formatDuration(double totalSeconds) {
    final minutes = (totalSeconds / 60).floor().toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).floor().toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (selectedDay == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.noActivitiesYet, style: const TextStyle(fontSize: 14, color: Color(0xFF595C5D))),
        ),
      );
    }

    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (data == null) {
      return const SizedBox.shrink();
    }

    final summary = data!['summary'] as Map<String, dynamic>;
    final routes = List<Map<String, dynamic>>.from(data!['routes'] ?? []);

    if (routes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(l10n.noActivitiesOnDay, style: const TextStyle(fontSize: 14, color: Color(0xFF595C5D)))),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.dailyWorkoutSummary(summary['totalCount'] as int, summary['completedCount'] as int, summary['attemptedCount'] as int),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF595C5D)),
        ),
        const SizedBox(height: 16),
        ...routes.map((route) => _DailyRouteCard(route: route, formatDuration: _formatDuration)),
      ],
    );
  }
}

class _DailyRouteCard extends StatelessWidget {
  final Map<String, dynamic> route;
  final String Function(double) formatDuration;

  const _DailyRouteCard({required this.route, required this.formatDuration});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final snapshot = route['routeSnapshot'] as Map<String, dynamic>;
    final title = snapshot['title'] as String? ?? '';
    final grade = snapshot['grade'] as String? ?? '';
    final gradeColorHex = snapshot['gradeColor'] as String?;
    final placeName = snapshot['placeName'] as String? ?? '';
    final imageUrl = snapshot['overlayImageUrl'] as String? ?? snapshot['imageUrl'] as String?;

    final completedCount = route['completedCount'] as int;
    final attemptedCount = route['attemptedCount'] as int;
    final totalDuration = (route['totalDuration'] as num).toDouble();

    final gradeColor = gradeColorHex != null
        ? Color(int.parse(gradeColorHex.replaceFirst('#', ''), radix: 16) | 0xFF000000)
        : const Color(0xFF0066FF);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x0A2C2F30), blurRadius: 16, offset: Offset(0, 4))],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
              child: Container(
                width: 150, height: 150,
                color: const Color(0xFFF0F0F0),
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: toThumbnailUrl(imageUrl, 's200'),
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const Icon(Icons.terrain, color: Color(0xFFDADDDF)),
                        errorWidget: (_, __, ___) => const Icon(Icons.terrain, color: Color(0xFFDADDDF)),
                      )
                    : const Icon(Icons.terrain, color: Color(0xFFDADDDF)),
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 150,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top: grade + title + place
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(color: gradeColor, borderRadius: BorderRadius.circular(6)),
                            child: Text(grade, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                          const SizedBox(height: 6),
                          Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF2C2F30))),
                          const SizedBox(height: 2),
                          Text(placeName, style: const TextStyle(fontSize: 12, color: Color(0xFF595C5D))),
                        ],
                      ),
                      // Bottom: big send count + sub stats
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$completedCount',
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF0066FF), height: 1),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l10n.completed.toUpperCase(),
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF999999)),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$attemptedCount ${l10n.attempted}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF595C5D)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l10n.totalDurationLabel(formatDuration(totalDuration)),
                                style: const TextStyle(fontSize: 11, color: Color(0xFF595C5D)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/http_client.dart';

class NotificationSettingsPage extends ConsumerStatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  ConsumerState<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState
    extends ConsumerState<NotificationSettingsPage> {
  bool _loading = true;
  bool _saving = false;
  bool _consent = false;
  DateTime? _consentAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await AuthorizedHttpClient.get('/users/me');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final consent = data['marketing_push_consent'] == true;
        final consentAtRaw = data['marketing_push_consent_at'] as String?;
        if (mounted) {
          setState(() {
            _consent = consent;
            _consentAt =
                consentAtRaw != null ? DateTime.tryParse(consentAtRaw) : null;
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.errorOccurred),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.errorOccurred),
          ),
        );
      }
    }
  }

  Future<void> _toggle(bool next) async {
    if (_saving) return;
    final previous = _consent;
    setState(() {
      _saving = true;
      _consent = next;
    });
    try {
      final response = await AuthorizedHttpClient.patch(
        '/my/marketing-consent',
        body: {'consent': next},
      );
      if (response.statusCode == 204) {
        if (mounted) {
          setState(() {
            _consentAt = next ? DateTime.now().toUtc() : null;
            _saving = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _consent = previous;
            _saving = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.errorOccurred),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _consent = previous;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.errorOccurred),
          ),
        );
      }
    }
  }

  String _subtitle(AppLocalizations l10n) {
    if (!_consent) {
      return l10n.marketingPushSettingSubtitleOff;
    }
    final at = _consentAt;
    final dateStr = at != null
        ? DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag())
            .format(at.toLocal())
        : '';
    return l10n.marketingPushSettingSubtitleOn(dateStr);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notifications)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  title: Text(l10n.marketingPushSettingTitle),
                  subtitle: Text(_subtitle(l10n)),
                  value: _consent,
                  onChanged: _saving ? null : _toggle,
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    l10n.marketingPushSettingsNoticeOperational,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Text(
                    l10n.marketingPushSettingsNoticeNight,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
    );
  }
}

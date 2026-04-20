import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import '../providers/auth_provider.dart';
import '../services/http_client.dart';
import 'notification_settings_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({Key? key}) : super(key: key);

  Future<void> _openSystemLanguageSettings() async {
    if (Platform.isIOS) {
      const url = 'app-settings:';
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url));
      }
    } else if (Platform.isAndroid) {
      const url = 'package:com.android.settings';
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.settings),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(AppLocalizations.of(context)!.languageSettings),
            onTap: _openSystemLanguageSettings,
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: Text(AppLocalizations.of(context)!.notifications),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NotificationSettingsPage(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(AppLocalizations.of(context)!.logout),
            onTap: () {
              showDialog(
                context: context,
                builder: (dialogContext) {
                  return AlertDialog(
                    title: Text(AppLocalizations.of(dialogContext)!.logout),
                    content: Text(AppLocalizations.of(dialogContext)!.confirmLogout),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text(AppLocalizations.of(dialogContext)!.cancel),
                      ),
                      TextButton(
                        onPressed: () async {
                          try {
                            await ref.read(authProvider.notifier).logout();
                            if (context.mounted) {
                              Navigator.of(context).pushNamedAndRemoveUntil(
                                '/login',
                                (route) => false,
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(AppLocalizations.of(context)!.errorOccurred),
                                ),
                              );
                            }
                          }
                        },
                        child: Text(AppLocalizations.of(dialogContext)!.confirm),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(
              AppLocalizations.of(context)!.deleteAccount,
            ),
            onTap: () => _showDeleteAccountDialog(context, ref),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(AppLocalizations.of(dialogContext)!.deleteAccount),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(AppLocalizations.of(dialogContext)!.deleteAccountWarning),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(dialogContext)!.deleteAccountConfirmHint,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(AppLocalizations.of(dialogContext)!.cancel),
                ),
                TextButton(
                  onPressed: controller.text.toLowerCase() == 'delete'
                      ? () async {
                          Navigator.pop(dialogContext);
                          await _deleteAccount(context, ref);
                        }
                      : null,
                  child: Text(
                    AppLocalizations.of(dialogContext)!.deleteAccount,
                    style: TextStyle(
                      color: controller.text.toLowerCase() == 'delete'
                          ? Colors.red
                          : null,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    try {
      final response = await AuthorizedHttpClient.delete('/users/me');
      if (response.statusCode == 204) {
        await ref.read(authProvider.notifier).logout();
        if (context.mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/login',
            (route) => false,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.accountDeleted),
            ),
          );
        }
      } else {
        throw Exception('Failed to delete account');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.failedDeleteAccount),
          ),
        );
      }
    }
  }
} 
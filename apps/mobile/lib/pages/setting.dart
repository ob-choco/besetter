import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import '../providers/auth_provider.dart';

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
        ],
      ),
    );
  }
} 
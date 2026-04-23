import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../services/legal_urls.dart';
import 'terms_page.dart' show WebViewPage;

class TermsAndPoliciesPage extends StatelessWidget {
  const TermsAndPoliciesPage({super.key});

  void _openLegalDocument(BuildContext context, LegalDocument kind, String title) {
    final locale = Localizations.localeOf(context).languageCode;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebViewPage(
          url: legalDocumentUrl(kind, locale),
          title: title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.termsAndPolicies)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: Text(l10n.termsOfService),
            onTap: () => _openLegalDocument(
              context,
              LegalDocument.serviceTerms,
              l10n.termsOfService,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(l10n.privacyPolicy),
            onTap: () => _openLegalDocument(
              context,
              LegalDocument.privacyPolicy,
              l10n.privacyPolicy,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text(l10n.locationBasedServicesTerms),
            onTap: () => _openLegalDocument(
              context,
              LegalDocument.locationTerms,
              l10n.locationBasedServicesTerms,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(l10n.openSourceLicenses),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'BESETTER',
            ),
          ),
        ],
      ),
    );
  }
}

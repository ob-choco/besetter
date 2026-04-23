enum LegalDocument { serviceTerms, privacyPolicy, locationTerms }

const Map<String, String> _serviceTerms = {
  'ko': 'https://truth-crafter-0c7.notion.site/1f2ad66660f1809ca756d8425c829e9a',
  'en': 'https://truth-crafter-0c7.notion.site/Terms-of-Use-1f2ad66660f18048b71eff109b16a3e0',
  'es': 'https://truth-crafter-0c7.notion.site/T-rminos-y-Condiciones-de-Uso-1f2ad66660f1803d817dc40d21386327',
  'ja': 'https://truth-crafter-0c7.notion.site/1f2ad66660f18036ba13d9c3947aa831',
};

const Map<String, String> _privacyPolicy = {
  'ko': 'https://truth-crafter-0c7.notion.site/1abad66660f1800ca144d8645ac8fc75',
  'en': 'https://truth-crafter-0c7.notion.site/Privacy-Policy-1f2ad66660f1808c9760d7b00c5d366f',
  'es': 'https://truth-crafter-0c7.notion.site/Pol-tica-de-Privacidad-1f2ad66660f181fd9d87cb068b896248',
  'ja': 'https://truth-crafter-0c7.notion.site/1f2ad66660f18161815ec804daaf4992',
};

const Map<String, String> _locationTerms = {
  'ko': 'https://truth-crafter-0c7.notion.site/348ad66660f1812a8c56dd8b3bbb5da8',
  'en': 'https://truth-crafter-0c7.notion.site/Location-Based-Services-Terms-of-Use-English-348ad66660f1818baab2e0c5bd7ad8dc',
  'es': 'https://truth-crafter-0c7.notion.site/T-rminos-de-uso-del-Servicio-Basado-en-Ubicaci-n-Espa-ol-348ad66660f181dab567e03c8978e2d4',
  'ja': 'https://truth-crafter-0c7.notion.site/348ad66660f18164b92ff73578a93362',
};

String legalDocumentUrl(LegalDocument kind, String locale) {
  Map<String, String> map;
  switch (kind) {
    case LegalDocument.serviceTerms:
      map = _serviceTerms;
      break;
    case LegalDocument.privacyPolicy:
      map = _privacyPolicy;
      break;
    case LegalDocument.locationTerms:
      map = _locationTerms;
      break;
  }
  return map[locale] ?? map['en']!;
}

const String contactEmail = 'contactus@olivebagel.com';

// Loopin — Acerca de: versión, licencia, privacidad, código, incidencias y
// licencias de terceros (Etapa 7a)
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine_controller.dart';
import '../l10n/strings.dart';
import 'theme.dart';

/// El código de Loopin.
const String kSourceUrl = 'https://github.com/alexoseayo40-cyber/loopin';

/// Abrir una incidencia nueva (con la plantilla que pide «Copiar resultados»).
const String kIssuesUrl = '$kSourceUrl/issues/new/choose';

/// Lo que va dentro de la app con su licencia: el texto está en los assets.
/// Apache 2.0 (Oboe) y OFL (las tipografías) piden que vaya con la app.
const List<({List<String> packages, String asset})> kThirdPartyLicenses = [
  (packages: ['Loopin'], asset: 'assets/licenses/loopin-GPL-3.0.txt'),
  (packages: ['Oboe'], asset: 'assets/licenses/oboe-Apache-2.0.txt'),
  (packages: ['SoundTouch'], asset: 'assets/licenses/soundtouch-LGPL-2.1.txt'),
  (packages: ['dr_libs (dr_wav, dr_mp3, dr_flac)'], asset: 'assets/licenses/dr_libs.txt'),
  (packages: ['Barlow Condensed'], asset: 'assets/fonts/OFL-barlowcondensed.txt'),
  (packages: ['Share Tech Mono'], asset: 'assets/fonts/OFL-sharetechmono.txt'),
  (packages: ['Virtuosity Drums'], asset: 'assets/drums/LICENSE.md'),
];

bool _registered = false;

/// Añade las licencias de [kThirdPartyLicenses] a la página de licencias de
/// Flutter (que ya trae las de Flutter y sus paquetes). Una vez.
void registerLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    for (final l in kThirdPartyLicenses) {
      final text = await rootBundle.loadString(l.asset);
      yield LicenseEntryWithLineBreaks(l.packages, text);
    }
  });
}

const _channel = MethodChannel('loopin/permissions');

/// Abre [url] en el navegador (la app no tiene permiso de internet).
Future<bool> openUrl(String url) async {
  try {
    return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
  } on PlatformException {
    return false;
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.controller});

  final EngineController controller;

  Future<void> _open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await openUrl(url)) {
      messenger.showSnackBar(SnackBar(content: Text(tr.aboutNoBrowser)));
    }
  }

  /// Copia el informe y abre una incidencia nueva.
  Future<void> _report(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: controller.report()));
    messenger.showSnackBar(SnackBar(content: Text(tr.aboutReportCopied)));
    if (!await openUrl(kIssuesUrl)) {
      messenger.showSnackBar(SnackBar(content: Text(tr.aboutNoBrowser)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final p = LoopinPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr.aboutTitle)),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final version = c.appVersion;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr.appName.toUpperCase(), style: p.label(size: 30, spacing: 8)),
                        const SizedBox(height: 4),
                        Text(tr.aboutTagline, style: theme.textTheme.bodyLarge),
                        if (version.isNotEmpty)
                          Text(
                            tr.aboutVersion(version),
                            key: const ValueKey('about-version'),
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.volunteer_activism_outlined),
                    title: Text(tr.aboutLicenseTitle),
                    subtitle: Text(tr.aboutLicenseLine),
                  ),
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(tr.aboutPrivacyTitle),
                    subtitle: Text(tr.aboutPrivacyLine),
                  ),
                  const Divider(),
                  ListTile(
                    key: const ValueKey('about-source'),
                    leading: const Icon(Icons.code),
                    title: Text(tr.aboutSource),
                    subtitle: Text(tr.aboutSourceLine),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => _open(context, kSourceUrl),
                  ),
                  ListTile(
                    key: const ValueKey('about-report'),
                    leading: const Icon(Icons.bug_report_outlined),
                    title: Text(tr.aboutReport),
                    subtitle: Text(tr.aboutReportLine),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => _report(context),
                  ),
                  ListTile(
                    key: const ValueKey('about-licenses'),
                    leading: const Icon(Icons.description_outlined),
                    title: Text(tr.aboutLicenses),
                    subtitle: Text(tr.aboutLicensesLine),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      registerLicenses();
                      showLicensePage(
                        context: context,
                        applicationName: tr.appName,
                        applicationVersion: version,
                        applicationLegalese: tr.aboutLegalese,
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

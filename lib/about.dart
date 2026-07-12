import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';
import 'widgets.dart';

/// Where the "Buy me a coffee" button points; change the handle here if the
/// page ever moves.
const String supportUrl = 'https://buymeacoffee.com/invertium';

/// Public home of the project.
const String sourceUrl = 'https://github.com/invertium/bms_app';

/// Shows the app's about dialog: version, support link, source link, and the
/// bundled open-source license notices.
Future<void> showAboutBmsDialog(BuildContext context) async {
  final info = await PackageInfo.fromPlatform();
  if (!context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (context) => _AboutDialog(version: info.version),
  );
}

class _AboutDialog extends StatelessWidget {
  const _AboutDialog({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: BmsColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const GradientBoltMark(size: 30),
                const SizedBox(width: 8),
                Text(
                  'BMS Dash',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Version $version',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: BmsColors.textMuted),
            ),
            const SizedBox(height: 14),
            Text(
              'Free, open-source monitoring and control for JBD / Xiaoxiang '
              'smart BMS over Bluetooth LE.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: BmsColors.textSecondary),
            ),
            const SizedBox(height: 20),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: BmsColors.accent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => _openLink(context, supportUrl),
                icon: const Icon(Icons.coffee),
                label: const Text(
                  'Buy me a coffee',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => _openLink(context, sourceUrl),
              icon: const Icon(Icons.code, size: 18),
              label: const Text('Source on GitHub'),
            ),
            TextButton(
              // Pushed on top of the dialog so back returns here.
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'BMS Dash',
                applicationVersion: version,
              ),
              child: const Text('Open-source licenses'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLink(BuildContext context, String url) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/legal_config.dart';

/// Privacy policy + OSS licenses. Home-adjacent only — not on the editor.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final uri = Uri.parse(LegalConfig.privacyPolicyUrl);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        _showLaunchError(context);
      }
    } catch (_) {
      if (context.mounted) _showLaunchError(context);
    }
  }

  void _showLaunchError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open the privacy policy.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        children: [
          ListTile(
            key: const Key('about-privacy-policy-tile'),
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            subtitle: const Text('Opens in your browser'),
            onTap: () => _openPrivacyPolicy(context),
          ),
          ListTile(
            key: const Key('about-oss-licenses-tile'),
            leading: const Icon(Icons.description_outlined),
            title: const Text('Open Source Licenses'),
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'Lowpoly Maker',
                applicationVersion: '1.0.0',
              );
            },
          ),
        ],
      ),
    );
  }
}

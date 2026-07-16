import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_info.dart';

const _kDocsUrl = 'https://scottkirvan.github.io/QuKi-Notes/';
const _kGithubUrl = 'https://github.com/ScottKirvan/QuKi-Notes';

Future<void> showHelpDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _HelpDialog(),
  );
}

class _HelpDialog extends StatelessWidget {
  const _HelpDialog();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'media/QuKiNotes_v2_Rainbow_transparent.png',
                width: 64,
                height: 64,
              ),
            ),
            const SizedBox(height: 10),
            Text(kAppName, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snap) => Text(
                'v${snap.data?.version ?? '…'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
            const SizedBox(height: 24),
            _LinkRow(
              icon: LucideIcons.bookOpen,
              title: 'Documentation',
              desc: 'Official guide and setup instructions.',
              label: 'Visit',
              url: _kDocsUrl,
              accent: true,
            ),
            const SizedBox(height: 12),
            _LinkRow(
              icon: LucideIcons.externalLink,
              title: 'GitHub',
              desc: 'Source code, issues, and release notes.',
              label: 'View',
              url: _kGithubUrl,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.title,
    required this.desc,
    required this.label,
    required this.url,
    this.accent = false,
  });

  final IconData icon;
  final String title;
  final String desc;
  final String label;
  final String url;
  final bool accent;

  Future<void> _open() async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              Text(
                desc,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        accent
            ? FilledButton(onPressed: _open, child: Text(label))
            : OutlinedButton(onPressed: _open, child: Text(label)),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_info.dart';

const _kDocsUrl = 'https://www.scottkirvan.com/QuKi-Notes/';
const _kDiscordUrl = 'https://discord.gg/TN6XJSNK5Y';
const _kGithubUrl = 'https://github.com/ScottKirvan/QuKi-Notes';

// Same SVG as BojuBot AboutModal.
const _kDiscordSvg = '''
<svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg"
  fill="none" stroke="currentColor" stroke-width="3"
  stroke-linecap="round" stroke-linejoin="round"
  width="100%" height="100%">
  <path d="M17.59,34.1733c-.89,1.3069-1.8944,2.6152-2.91,3.8267C7.3,37.79,4.5,33,4.5,33A44.83,44.83,0,0,1,9.31,13.48,16.47,16.47,0,0,1,18.69,10l1,2.31A32.6875,32.6875,0,0,1,24,12a32.9643,32.9643,0,0,1,4.33.3l1-2.31a16.47,16.47,0,0,1,9.38,3.51A44.8292,44.8292,0,0,1,43.5,33s-2.8,4.79-10.18,5a47.4193,47.4193,0,0,1-2.86-3.81m6.46-2.9c-3.84,1.9454-7.5555,3.89-12.92,3.89s-9.08-1.9446-12.92-3.89"/>
  <circle cx="17.847" cy="26.23" r="3.35"/>
  <circle cx="30.153" cy="26.23" r="3.35"/>
</svg>
''';

// Lucide GitHub icon.
const _kGithubSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"
  fill="none" stroke="currentColor" stroke-width="2"
  stroke-linecap="round" stroke-linejoin="round">
  <path d="M15 22v-4a4.8 4.8 0 0 0-1-3.5c3 0 6-2 6-5.5.08-1.25-.27-2.48-1-3.5.28-1.15.28-2.35 0-3.5 0 0-1 0-3 1.5-2.64-.5-5.36-.5-8 0C6 2 5 2 5 2c-.3 1.15-.3 2.35 0 3.5A5.403 5.403 0 0 0 4 9c0 3.5 3 5.5 6 5.5-.39.49-.68 1.05-.85 1.65-.17.6-.22 1.23-.15 1.85v4"/>
  <path d="M9 18c-4.51 2-5-2-7-2"/>
</svg>
''';

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
              icon: const Icon(LucideIcons.bookOpen, size: 20),
              title: 'Documentation',
              desc: 'Official guide and setup instructions.',
              label: 'Visit',
              url: _kDocsUrl,
              accent: true,
            ),
            const SizedBox(height: 12),
            _LinkRow(
              icon: _SvgIcon(svg: _kDiscordSvg),
              title: 'Discord',
              desc: 'Chat with other QuKi-Notes users and get support.',
              label: 'Join',
              url: _kDiscordUrl,
            ),
            const SizedBox(height: 12),
            _LinkRow(
              icon: _SvgIcon(svg: _kGithubSvg),
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

class _SvgIcon extends StatelessWidget {
  const _SvgIcon({required this.svg});
  final String svg;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    return SvgPicture.string(
      svg,
      width: 20,
      height: 20,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
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

  final Widget icon;
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
        icon,
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

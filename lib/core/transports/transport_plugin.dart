// ADR-14: Transport plugin contract.
// ADR-21: lib/core/transports/ imports Flutter for Widget/WidgetRef because
// settingsView() is part of the plugin contract. The CLI (ADR-16), if built,
// uses only toss() and ignores settingsView().
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class TransportPlugin {
  const TransportPlugin();

  String get id;
  String get displayName;
  String get description;

  // Returns a configuration widget shown in Settings → Tosses.
  // Default: "No configuration needed."
  Widget settingsView(WidgetRef ref) => const _NoConfigView();

  Future<TossResult> toss({
    required String markdown,
    required List<TossImage> images,
    required TossContext ctx,
  });
}

class TossResult {
  const TossResult({
    required this.success,
    this.message,
    this.retryable = false,
  });

  final bool success;
  final String? message;
  final bool retryable;
}

class TossContext {
  const TossContext({
    required this.firedAt,
    required this.quki,
    this.gps,
    this.userOverrides = const {},
  });

  final DateTime firedAt;
  final QukiMetadata quki;
  // null until ADR-19 GPS gates are implemented (Phase 3).
  final Geolocation? gps;
  final Map<String, String> userOverrides;
}

class QukiMetadata {
  const QukiMetadata({
    required this.id,
    required this.createdAt,
    required this.modifiedAt,
  });

  final String id;
  final DateTime createdAt;
  final DateTime modifiedAt;
}

class TossImage {
  const TossImage({required this.localPath, required this.markdownRef});

  final String localPath;
  final String markdownRef;
}

class Geolocation {
  const Geolocation({
    required this.latitude,
    required this.longitude,
    this.address,
  });

  final double latitude;
  final double longitude;
  final String? address;
}

class _NoConfigView extends StatelessWidget {
  const _NoConfigView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'No configuration needed.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

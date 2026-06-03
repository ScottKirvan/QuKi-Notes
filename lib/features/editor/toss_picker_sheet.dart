import 'package:flutter/material.dart';

import '../../core/transports/transport_plugin.dart';

class TossPickerSheet extends StatelessWidget {
  const TossPickerSheet({super.key, required this.plugins});

  final List<TransportPlugin> plugins;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Toss to…',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ...plugins.map(
            (p) => ListTile(
              title: Text(p.displayName),
              subtitle: Text(p.description),
              onTap: () => Navigator.pop(context, p),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

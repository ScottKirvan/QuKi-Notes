import 'transport_plugin.dart';

class TransportRegistry {
  const TransportRegistry({required this.plugins});

  final List<TransportPlugin> plugins;

  TransportPlugin? findById(String id) =>
      plugins.where((p) => p.id == id).firstOrNull;
}

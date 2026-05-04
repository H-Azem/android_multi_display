import 'panel_descriptor.dart';

enum PanelSlot {
  primary,
  secondary,
  tertiary,
}

class PanelActivation {
  const PanelActivation({
    required this.slot,
    required this.panel,
    required this.ready,
  });

  final PanelSlot slot;
  final PanelDescriptor panel;
  final bool ready;
}

import 'package:flutter/services.dart';

final panelBridge = PanelBridge();

class PanelBridge {
  static const EventChannel _hostToPanel =
      EventChannel('android_multi_display/panel_events');
  static const MethodChannel _panelToHost =
      MethodChannel('android_multi_display/panel_actions');

  final Set<void Function({required String action, dynamic payload})>
      _listeners = {};

  PanelBridge() {
    _hostToPanel.receiveBroadcastStream().listen((event) {
      if (event is! Map) return;
      final action = (event['action'] ?? '').toString();
      for (final listener in _listeners) {
        listener(action: action, payload: event['payload']);
      }
    });
  }

  Future<bool> publish({
    required String action,
    dynamic payload,
  }) async {
    final result = await _panelToHost.invokeMethod<bool>(
      'panelToHost',
      <String, dynamic>{'action': action, 'payload': payload},
    );
    return result == true;
  }

  void addListener(
    void Function({required String action, dynamic payload}) listener,
  ) {
    _listeners.add(listener);
  }

  bool removeListener(
    void Function({required String action, dynamic payload}) listener,
  ) {
    return _listeners.remove(listener);
  }
}

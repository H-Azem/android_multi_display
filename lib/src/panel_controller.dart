import 'package:flutter/services.dart';

import 'contracts/panel_activation.dart';
import 'contracts/panel_descriptor.dart';
import 'contracts/panel_ordering.dart';

final panelController = PanelController();

class PanelController {
  /// Total screens supported: primary + two external panels. There is **no**
  /// fourth screen; activation never goes beyond three ordered displays.
  static const int orderedScreenLimit = 3;

  static const MethodChannel _methods =
      MethodChannel('android_multi_display/host_methods');
  static const EventChannel _events =
      EventChannel('android_multi_display/host_events');

  final Set<void Function(bool connected)> _connectionWatchers = {};
  final Set<void Function({required String action, dynamic payload})>
      _messageWatchers = {};
  Size? _lastCanvasSize;
  bool _isPlugged = false;
  bool _bootstrapped = false;

  bool get isPlugged => _isPlugged;
  Size? get lastCanvasSize => _lastCanvasSize;

  Future<void> bootstrap({
    String secondaryEntrypoint = 'secondaryDisplayMain',
    String tertiaryEntrypoint = 'tertiaryDisplayMain',
    /// Optional Dart library path containing the secondary entrypoint.
    /// Example: `package:my_app/panel_entry_points.dart`.
    String? secondaryLibrary,
    /// Optional Dart library path containing the tertiary entrypoint.
    String? tertiaryLibrary,
    /// Registers **every** Android plugin from the host [GeneratedPluginRegistrant] on panel
    /// engines. Prefer [panelPluginClassNames] when some plugins crash on secondary isolates
    /// (for example USB printers on Android 14+).
    bool registerAllPlugins = false,
    /// Fully-qualified Android plugin class names to register on panel engines only, e.g.
    /// `io.flutter.plugins.pathprovider.PathProviderPlugin` for [path_provider] /
    /// [cached_network_image]. Copy names from your app's
    /// `android/.../GeneratedPluginRegistrant.java`.
    List<String> panelPluginClassNames = const [],
  }) async {
    if (!_bootstrapped) {
      _events.receiveBroadcastStream().listen(_handleEvent);
      _bootstrapped = true;
    }
    await _methods.invokeMethod<void>(
      'bootstrap',
      <String, dynamic>{
        'secondaryEntrypoint': secondaryEntrypoint,
        'tertiaryEntrypoint': tertiaryEntrypoint,
        if (secondaryLibrary != null) 'secondaryLibrary': secondaryLibrary,
        if (tertiaryLibrary != null) 'tertiaryLibrary': tertiaryLibrary,
        'registerAllPlugins': registerAllPlugins,
        'panelPluginClassNames': panelPluginClassNames,
      },
    );
  }

  Future<List<PanelDescriptor>> queryPanels({
    PanelOrdering ordering = const PanelOrdering(),
  }) async {
    final raw = await _methods.invokeMethod<List<Object?>>('queryPanels') ?? [];
    final panels = raw
        .whereType<Map<dynamic, dynamic>>()
        .map(PanelDescriptor.fromMap)
        .toList(growable: true);

    panels.sort((a, b) {
      final sort = _compare(a, b, ordering.key);
      if (sort != 0) {
        return ordering.direction == PanelSortDirection.ascending ? sort : -sort;
      }
      return a.id.compareTo(b.id);
    });
    return panels;
  }

  Future<bool> attachPanel({
    required String panelKey,
    required int panelId,
    /// Optional Dart entrypoint for this attach only (`@pragma('vm:entry-point')`).
    /// If null, uses the key configured in [bootstrap]: secondary vs tertiary.
    String? dartEntrypoint,
    /// Optional Dart library for [dartEntrypoint].
    String? dartLibrary,
  }) async {
    final result = await _methods.invokeMethod<Map<dynamic, dynamic>>(
      'attachPanel',
      <String, dynamic>{
        'panelKey': panelKey,
        'panelId': panelId,
        if (dartEntrypoint != null) 'dartEntrypoint': dartEntrypoint,
        if (dartLibrary != null) 'dartLibrary': dartLibrary,
      },
    );
    if (result == null) return false;
    _lastCanvasSize = Size(
      (result['width'] as num).toDouble(),
      (result['height'] as num).toDouble(),
    );
    return true;
  }

  Future<void> detachAllPanels() async {
    await _methods.invokeMethod<void>('detachAllPanels');
  }

  Future<void> detachPanel({
    required String panelKey,
  }) async {
    await _methods.invokeMethod<void>(
      'detachPanel',
      <String, dynamic>{'panelKey': panelKey},
    );
  }

  /// Drops whichever external session is bound to this [displayId] (hardware id).
  Future<bool> detachByDisplayId(int displayId) async {
    final removed = await _methods.invokeMethod<bool>(
      'detachByDisplayId',
      <String, dynamic>{'displayId': displayId},
    );
    return removed == true;
  }

  Future<List<PanelActivation>> activatePanels({
    PanelOrdering ordering = const PanelOrdering(),
    Duration readinessTimeout = const Duration(seconds: 10),
    /// Small delay between attaching external panels to reduce races on some devices/emulators.
    Duration attachStagger = const Duration(milliseconds: 80),
  }) async {
    final ordered = await queryPanels(ordering: ordering);
    if (ordered.isEmpty) {
      await detachAllPanels();
      return const [];
    }

    final selected = ordered.take(orderedScreenLimit).toList(growable: false);
    await detachAllPanels();

    final activations = <PanelActivation>[];
    final externals = <(String panelKey, PanelSlot slot, PanelDescriptor panel)>[];
    var externalIndex = 0;

    for (final panel in selected) {
      if (panel.primary) {
        activations.add(
          PanelActivation(slot: PanelSlot.primary, panel: panel, ready: true),
        );
        continue;
      }
      final key = externalIndex == 0 ? 'secondary' : 'tertiary';
      final slot = externalIndex == 0 ? PanelSlot.secondary : PanelSlot.tertiary;
      externalIndex++;
      externals.add((key, slot, panel));
    }

    // Attach externals as fast as possible, then wait readiness in parallel.
    final attachResults = <String, bool>{};
    for (final e in externals) {
      attachResults[e.$1] = await attachPanel(panelKey: e.$1, panelId: e.$3.id);
      // Stagger only between multiple external attaches.
      if (attachStagger.inMilliseconds > 0 && e.$1 == 'secondary' && externals.length > 1) {
        await Future<void>.delayed(attachStagger);
      }
    }

    final readiness = await Future.wait<bool>([
      for (final e in externals)
        attachResults[e.$1] == true
            ? waitPanelReady(panelKey: e.$1, timeout: readinessTimeout)
            : Future<bool>.value(false),
    ]);

    for (var i = 0; i < externals.length; i++) {
      final e = externals[i];
      activations.add(
        PanelActivation(slot: e.$2, panel: e.$3, ready: readiness[i]),
      );
    }

    return activations;
  }

  Future<bool> waitPanelReady({
    required String panelKey,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final ready = await _methods.invokeMethod<bool>(
      'waitPanelReady',
      <String, dynamic>{
        'panelKey': panelKey,
        'timeoutMs': timeout.inMilliseconds,
      },
    );
    return ready == true;
  }

  Future<bool> broadcast({
    required String action,
    dynamic payload,
  }) async {
    final sent = await _methods.invokeMethod<bool>(
      'broadcast',
      <String, dynamic>{'action': action, 'payload': payload},
    );
    return sent == true;
  }

  void watchConnection(void Function(bool connected) listener) {
    _connectionWatchers.add(listener);
  }

  bool unwatchConnection(void Function(bool connected) listener) {
    return _connectionWatchers.remove(listener);
  }

  void watchMessages(
    void Function({required String action, dynamic payload}) listener,
  ) {
    _messageWatchers.add(listener);
  }

  bool unwatchMessages(
    void Function({required String action, dynamic payload}) listener,
  ) {
    return _messageWatchers.remove(listener);
  }

  int _compare(PanelDescriptor a, PanelDescriptor b, PanelSortKey key) {
    return switch (key) {
      PanelSortKey.area => a.area.compareTo(b.area),
      PanelSortKey.width => a.width.compareTo(b.width),
      PanelSortKey.height => a.height.compareTo(b.height),
      PanelSortKey.id => a.id.compareTo(b.id),
      PanelSortKey.name => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    };
  }

  void _handleEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type'];
    if (type == 'plug') {
      _isPlugged = event['connected'] == true;
      if (!_isPlugged) _lastCanvasSize = null;
      for (final watcher in _connectionWatchers) {
        watcher(_isPlugged);
      }
      return;
    }
    if (type == 'message') {
      final action = (event['action'] ?? '').toString();
      for (final watcher in _messageWatchers) {
        watcher(action: action, payload: event['payload']);
      }
    }
  }
}

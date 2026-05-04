/// Host-only entry. Panel isolates live in [panel_entry_points.dart].
library;

import 'package:flutter/material.dart';
import 'package:android_multi_display/android_multi_display.dart';

import 'panel_entry_points.dart'
    show secondaryDisplayMain, tertiaryDisplayMain;

/// Ensure analyzer / tree-shaker keeps isolate entry symbols.
final List<void Function()> _panelExports = [
  secondaryDisplayMain,
  tertiaryDisplayMain,
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('_panelExports linked: ${_panelExports.length}');
  runApp(const _HostApplication());
}

class _HostApplication extends StatelessWidget {
  const _HostApplication();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Android multi display',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const _DemoPage(),
    );
  }
}

class _DemoPage extends StatefulWidget {
  const _DemoPage();

  @override
  State<_DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<_DemoPage> {
  final PanelController _controller = panelController;

  late final PanelOrdering _ordering;
  String _log = '';

  Future<void> _append(String text) async {
    setState(() {
      final line =
          '${TimeOfDay.now().hour.toString().padLeft(2, '0')}:${TimeOfDay.now().minute.toString().padLeft(2, '0')} $text\n';
      _log = '$line$_log'.trim();
      const maxLen = 2000;
      if (_log.length > maxLen) {
        _log = _log.substring(0, maxLen);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _ordering = const PanelOrdering(
      key: PanelSortKey.area,
      direction: PanelSortDirection.descending,
    );

    _controller.watchConnection(_listenPlug);
    _controller.watchMessages(_listenHostPayload);
    _bootstrap();
  }

  void _listenPlug(bool plugged) => _append('hardware plug broadcast: $plugged');

  void _listenHostPayload({required String action, dynamic payload}) {
    _append('from panel: $action $payload');
  }

  Future<void> _bootstrap() async {
    await _controller.bootstrap(
      secondaryEntrypoint: 'secondaryDisplayMain',
      tertiaryEntrypoint: 'tertiaryDisplayMain',  //Optional
      secondaryLibrary: 'package:android_multi_display_example/panel_entry_points.dart',  
      tertiaryLibrary: 'package:android_multi_display_example/panel_entry_points.dart',  //Optional
      registerAllPlugins: false,
      panelPluginClassNames: const [] //Optional
    );
    await _append('bootstrap done');
  }

  Future<void> _listDisplays() async {
    final list = await _controller.queryPanels(ordering: _ordering);
    await _append('displays: ${list.map((p) => '#${p.id} ${p.width}x${p.height} primary=${p.primary}').join('; ')}');
  }

  Future<void> _activateOrdered() async {
    final hits = await _controller.activatePanels(
      ordering: _ordering,
      readinessTimeout: const Duration(seconds: 12),
    );
    await _append(
      'activated: ${hits.map((a) => '${a.slot}->#${a.panel.id} ready=${a.ready}').join(', ')}',
    );
  }

  Future<void> _broadcastPing() async {
    final ok = await _controller.broadcast(
      action: 'demo_message',
      payload: {'tick': DateTime.now().millisecondsSinceEpoch},
    );
    await _append('broadcast demo_message -> $ok');
  }

  Future<void> _detachAll() async {
    await _controller.detachAllPanels();
    await _append('detachAllPanels done');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Android multi display example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Connect an external display, then Activate. '
              'Use Log to verify ordering (includes primary).\n'
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _listDisplays,
                  child: const Text('List displays'),
                ),
                FilledButton(
                  onPressed: _activateOrdered,
                  child: const Text('Activate displays'),
                ),
                FilledButton(
                  onPressed: _broadcastPing,
                  child: const Text('Broadcast to panels'),
                ),
                FilledButton(
                  onPressed: _detachAll,
                  child: const Text('Detach all'),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _log.isEmpty ? '—' : _log,
                
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

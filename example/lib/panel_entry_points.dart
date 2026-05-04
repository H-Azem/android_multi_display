/// Keeps isolate entry symbols linked from [main.dart].
library;

import 'package:flutter/material.dart';
import 'package:android_multi_display/panel_bridge.dart';

/// External panel A (typically "secondary").
@pragma('vm:entry-point')
void secondaryDisplayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _PanelChrome(label: 'Panel A', accent: Colors.indigoAccent));
}

/// External panel B (typically "tertiary").
@pragma('vm:entry-point')
void tertiaryDisplayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _PanelChrome(label: 'Panel B', accent: Colors.green));
}

class _PanelChrome extends StatefulWidget {
  const _PanelChrome({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  State<_PanelChrome> createState() => _PanelChromeState();
}

class _PanelChromeState extends State<_PanelChrome> {
  String _last = 'waiting for host';

  void _incoming({required String action, dynamic payload}) {
    if (!mounted) return;
    final text = '$action:${payload ?? ''}';
    setState(() => _last = text.length > 200 ? '${text.substring(0, 197)}…' : text);
  }

  @override
  void initState() {
    super.initState();
    panelBridge.addListener(_incoming);
  }

  @override
  void dispose() {
    panelBridge.removeListener(_incoming);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.grey.shade900,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: widget.accent,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                Text(
                  _last,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: Colors.white70),
                ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: widget.accent),
                  onPressed: () async {
                    await panelBridge.publish(
                      action: 'panel_ping',
                      payload: {'label': widget.label},
                    );
                  },
                  child: const Text('Send ping to host'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

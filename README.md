# android_multi_display

![Overview](https://raw.githubusercontent.com/H-Azem/android_multi_display/main/assets/screenshots/banner.png)

Android Flutter plugin for managing **multiple external displays** with **independent UI rendering** and **real-time data communication** between screens.

---

## ✨ Features

* Support up to **3 ordered displays** (primary + secondary + tertiary)
* Render **independent Flutter UI** on each screen
* **Real-time bidirectional messaging** (host ↔ panels)
* Fine control over display ordering and attachment

---

## 📸 Preview

![Demo](https://raw.githubusercontent.com/H-Azem/android_multi_display/main/assets/gifs/demo.gif)

---


## 🧠 How it works

* Main app = **Host (primary display)**
* External screens = **Panels (secondary / tertiary)**
* Communication:

  * Host → Panels: `broadcast`
  * Panels → Host: `panelBridge`

---


## 🔧 Basic Usage

```dart
final controller = PanelController();

await controller.bootstrap(
  secondaryEntrypoint: 'secondaryDisplayMain',
  tertiaryEntrypoint: 'tertiaryDisplayMain', //Optional
);

await controller.activatePanels();
```

---

## 🔄 Messaging

### Host → Panels (send from main app)

```dart
await controller.broadcast(
  action: 'demo_message',
  payload: {'tick': DateTime.now().millisecondsSinceEpoch},
);
```

Receive on panel entrypoint (`secondaryDisplayMain` / `tertiaryDisplayMain`):

```dart
import 'package:android_multi_display/panel_bridge.dart';

void _incoming({required String action, dynamic payload}) {
  debugPrint('from host: $action $payload');
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
```

### Panels → Host (send from panel)

```dart
await panelBridge.publish(
  action: 'panel_ping',
  payload: {'label': 'Panel A'},
);
```

Receive on host:

```dart
void _listenHostPayload({required String action, dynamic payload}) {
  debugPrint('from panel: $action $payload');
}

@override
void initState() {
  super.initState();
  controller.watchMessages(_listenHostPayload);
}
```

---

## 🧩 Panel Plugins

If you need to use Flutter plugins inside panel screens (like `path_provider`), you must register them during `bootstrap`.

```dart
await controller.bootstrap(
  secondaryEntrypoint: 'secondaryDisplayMain',
  tertiaryEntrypoint: 'tertiaryDisplayMain',  //Optional
  panelPluginClassNames: const [
    'io.flutter.plugins.pathprovider.PathProviderPlugin',
  ],
);
```

---

## 🤝 Contributing

Contributions are welcome!

If you have ideas, improvements, or bug fixes, feel free to open an issue or pull request on GitHub.

This plugin was partly inspired by external_display but redesigned with a focus on **multi-display orchestration and messaging**.

---

## ☕ Support / Donate

If this plugin helped you, consider supporting development:

### 💳 Card Payment
https://yekpay.io/en/azemdev

### 🪙 Crypto
**USDT (TRC20):**
`TJnFcaM8v4s5RVfo9H3jc38tH1HwdA2PkV`

---


## 📄 License

MIT License

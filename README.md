# android_multi_display

![Demo](https://raw.githubusercontent.com/H-Azem/android_multi_display/main/assets/gifs/demo.gif)

Android Flutter plugin for managing **multiple external displays** with **independent UI rendering** and **real-time data communication** between screens.

---

## ✨ Features

* Support up to **3 ordered displays** (primary + secondary + tertiary)
* Render **independent Flutter UI** on each screen
* **Real-time bidirectional messaging** (host ↔ panels)
* Fine control over display ordering and attachment

---

## 📸 Preview

![Overview](https://raw.githubusercontent.com/H-Azem/android_multi_display/main/assets/screenshots/banner.png)

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

Send data from host:

```dart
controller.broadcast({"type": "ping"});
```

Receive on panel:

```dart
PanelBridge.publish({"type": "pong"});
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

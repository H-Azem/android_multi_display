package com.azemdev.multidisplay

import android.app.Presentation
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Display
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.util.GeneratedPluginRegister
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap

private data class PanelSession(
    val key: String,
    val panelId: Int,
    val engine: FlutterEngine,
    var presentation: Presentation? = null,
    var flutterView: FlutterView? = null,
    var sink: EventChannel.EventSink? = null
)

private const val TAG = "AndroidMultiDisplay"

private const val CHANNEL_HOST_METHODS = "android_multi_display/host_methods"
private const val CHANNEL_HOST_EVENTS = "android_multi_display/host_events"
private const val CHANNEL_PANEL_ACTIONS = "android_multi_display/panel_actions"
private const val CHANNEL_PANEL_EVENTS = "android_multi_display/panel_events"

class AndroidMultiDisplayPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, DisplayManager.DisplayListener {

    private lateinit var appContext: Context
    private lateinit var displayManager: DisplayManager
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel

    private val sessions = ConcurrentHashMap<String, PanelSession>()
    private val handler = Handler(Looper.getMainLooper())
    private var secondaryEntrypoint = "secondaryDisplayMain"
    private var tertiaryEntrypoint = "tertiaryDisplayMain"
    private var secondaryLibrary: String? = null
    private var tertiaryLibrary: String? = null
    /** When true, runs the host app's full [GeneratedPluginRegistrant] on each panel engine. */
    private var registerAllPluginsForPanels: Boolean = false

    /**
     * Fully-qualified Android plugin classes to register on panel engines only.
     * Use this to enable [path_provider], [sqflite], etc. without pulling in every host plugin.
     */
    private val panelPluginClassNames = mutableListOf<String>()
    private var hostSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        displayManager =
            appContext.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        methods = MethodChannel(binding.binaryMessenger, CHANNEL_HOST_METHODS)
        events = EventChannel(binding.binaryMessenger, CHANNEL_HOST_EVENTS)
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        sessions.values.toList().forEach { clearSession(it, true) }
        sessions.clear()
        displayManager.unregisterDisplayListener(this)
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "bootstrap" -> {
                call.argument<String>("secondaryEntrypoint")?.let {
                    if (it.isNotBlank()) secondaryEntrypoint = it
                }
                call.argument<String>("tertiaryEntrypoint")?.let {
                    if (it.isNotBlank()) tertiaryEntrypoint = it
                }
                call.argument<String>("secondaryLibrary")?.let {
                    secondaryLibrary = it.takeIf { lib -> lib.isNotBlank() }
                }
                call.argument<String>("tertiaryLibrary")?.let {
                    tertiaryLibrary = it.takeIf { lib -> lib.isNotBlank() }
                }
                call.argument<Boolean>("registerAllPlugins")?.let {
                    registerAllPluginsForPanels = it
                }
                call.argument<List<*>>("panelPluginClassNames")?.let { list ->
                    panelPluginClassNames.clear()
                    for (item in list) {
                        val s = item as? String
                        if (!s.isNullOrBlank()) panelPluginClassNames.add(s.trim())
                    }
                }
                result.success(true)
            }

            "queryPanels" -> {
                result.success(readPanels())
            }

            "attachPanel" -> {
                val panelKey = call.argument<String>("panelKey") ?: "secondary"
                val panelId = call.argument<Int>("panelId")
                val dartEntrypoint = call.argument<String>("dartEntrypoint")
                val dartLibrary = call.argument<String>("dartLibrary")
                val display = if (panelId == null) null else displayManager.getDisplay(panelId)
                if (display == null || display.displayId == Display.DEFAULT_DISPLAY) {
                    result.success(null)
                    return
                }
                try {
                    val session = createSession(panelKey, display, dartEntrypoint, dartLibrary)
                    result.success(resolution(session.panelId, display))
                } catch (error: Throwable) {
                    result.error(
                        "PANEL_ATTACH_FAILED",
                        error.message ?: "Unknown attach failure",
                        null
                    )
                }
            }

            "detachPanel" -> {
                val panelKey = call.argument<String>("panelKey") ?: "secondary"
                sessions.remove(panelKey)?.let { clearSession(it, true) }
                result.success(true)
            }

            "detachByDisplayId" -> {
                val displayId = call.argument<Int>("displayId")
                if (displayId == null) {
                    result.success(false)
                    return
                }
                val keys = sessions.filter { it.value.panelId == displayId }.keys.toList()
                keys.forEach { key ->
                    sessions.remove(key)?.let { clearSession(it, true) }
                }
                result.success(keys.isNotEmpty())
            }

            "detachAllPanels" -> {
                sessions.values.toList().forEach { clearSession(it, true) }
                sessions.clear()
                result.success(true)
            }

            "waitPanelReady" -> {
                val panelKey = call.argument<String>("panelKey") ?: "secondary"
                val timeoutMs = call.argument<Int>("timeoutMs") ?: 10000
                awaitReadiness(panelKey, timeoutMs, result)
            }

            "broadcast" -> {
                val payload = call.arguments
                var didSend = false
                sessions.values.forEach { session ->
                    val sink = session.sink
                    if (sink != null) {
                        sink.success(payload)
                        didSend = true
                    }
                }
                result.success(didSend)
            }

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        hostSink = events
        emitPlugEvent(readPanels().any { it["primary"] == false })
        displayManager.registerDisplayListener(this, handler)
    }

    override fun onCancel(arguments: Any?) {
        displayManager.unregisterDisplayListener(this)
        hostSink = null
    }

    override fun onDisplayAdded(displayId: Int) {
        emitPlugEvent(true)
    }

    override fun onDisplayRemoved(displayId: Int) {
        sessions.values.filter { it.panelId == displayId }.forEach {
            clearSession(it, true)
            sessions.remove(it.key)
        }
        emitPlugEvent(readPanels().any { it["primary"] == false })
    }

    override fun onDisplayChanged(displayId: Int) {}

    private fun registerPluginByFqcn(engine: FlutterEngine, fqcn: String) {
        if (fqcn.isBlank()) return
        if (fqcn == AndroidMultiDisplayPlugin::class.java.name) {
            Log.w(
                TAG,
                "Skipping $fqcn on panel engine (plugin must stay on host engine only)."
            )
            return
        }
        try {
            val clazz = Class.forName(fqcn)
            val instance = clazz.getDeclaredConstructor().newInstance()
            if (instance !is FlutterPlugin) {
                Log.e(TAG, "Not a FlutterPlugin: $fqcn")
                return
            }
            engine.plugins.add(instance)
        } catch (e: Throwable) {
            Log.e(TAG, "Failed to register panel plugin: $fqcn", e)
        }
    }

    private fun createSession(
        panelKey: String,
        display: Display,
        dartEntrypoint: String?,
        dartLibrary: String?
    ): PanelSession {
        sessions.remove(panelKey)?.let { clearSession(it, true) }

        // Disable auto generated-plugin registration for panel engines.
        val engine = FlutterEngine(appContext, null, false, false)
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(appContext)
        loader.ensureInitializationComplete(appContext, null)

        val session = PanelSession(panelKey, display.displayId, engine)
        sessions[panelKey] = session

        val entrypoint = dartEntrypoint?.takeIf { it.isNotBlank() }
            ?: if (panelKey == "tertiary") tertiaryEntrypoint else secondaryEntrypoint
        val library = dartLibrary?.takeIf { it.isNotBlank() }
            ?: if (panelKey == "tertiary") tertiaryLibrary else secondaryLibrary

        val dart = if (library == null) {
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), entrypoint)
        } else {
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), library, entrypoint)
        }

        when {
            registerAllPluginsForPanels -> {
                GeneratedPluginRegister.registerGeneratedPlugins(engine)
            }
            panelPluginClassNames.isNotEmpty() -> {
                for (fqcn in panelPluginClassNames) {
                    registerPluginByFqcn(engine, fqcn)
                }
            }
        }

        // Register panel channels before Dart starts so isolate Method/Event subscriptions
        // never race a missing native handler; keep [sessions] populated before onListen.
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_PANEL_ACTIONS)
            .setMethodCallHandler { call, result ->
                if (call.method == "panelToHost") {
                    val payload = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                    val forwarded = mapOf(
                        "type" to "message",
                        "panelKey" to panelKey,
                        "action" to (payload["action"] ?: "").toString(),
                        "payload" to payload["payload"]
                    )
                    val sink = hostSink
                    try {
                        sink?.success(forwarded)
                    } catch (e: Exception) {
                        Log.e(TAG, "panelToHost: failed to emit on host stream", e)
                    }
                    result.success(sink != null)
                } else {
                    result.notImplemented()
                }
            }

        EventChannel(engine.dartExecutor.binaryMessenger, CHANNEL_PANEL_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
                    sessions[panelKey]?.sink = eventSink
                }

                override fun onCancel(arguments: Any?) {
                    sessions[panelKey]?.sink = null
                }
            })

        engine.dartExecutor.executeDartEntrypoint(dart)
        engine.lifecycleChannel.appIsResumed()
        engine.platformViewsController.attach(appContext, engine.renderer, engine.dartExecutor)

        wirePresentation(session, display)
        return session
    }

    private fun wirePresentation(session: PanelSession, display: Display) {
        val presentation = Presentation(appContext, display)
        val displayContext = presentation.context
        // Texture rendering is significantly more reliable for multi-display on emulators
        // and reduces SurfaceSyncGroup timing issues that can lead to white panels.
        val view = FlutterView(displayContext, RenderMode.texture, TransparencyMode.opaque)
        view.attachToFlutterEngine(session.engine)
        session.engine.lifecycleChannel.appIsResumed()
        val holder = FrameLayout(displayContext).apply {
            addView(
                view,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            )
        }
        presentation.setContentView(holder)
        presentation.show()
        // Ensure first frame is scheduled even if the system doesn't dispatch input yet.
        view.post {
            view.requestFocus()
            view.invalidate()
        }
        session.flutterView = view
        session.presentation = presentation
    }

    private fun clearSession(session: PanelSession, destroy: Boolean) {
        try {
            session.flutterView?.detachFromFlutterEngine()
        } catch (_: Exception) {
        }
        try {
            session.presentation?.dismiss()
        } catch (_: Exception) {
        }
        session.flutterView = null
        session.presentation = null
        session.sink = null
        if (destroy) {
            try {
                session.engine.lifecycleChannel.appIsDetached()
                session.engine.destroy()
            } catch (_: Exception) {
            }
        }
    }

    private fun awaitReadiness(
        panelKey: String,
        timeoutMs: Int,
        result: MethodChannel.Result
    ) {
        val started = System.currentTimeMillis()
        fun tick() {
            if (sessions[panelKey]?.sink != null) {
                result.success(true)
                return
            }
            if (System.currentTimeMillis() - started >= timeoutMs) {
                result.success(false)
                return
            }
            handler.postDelayed(::tick, 100)
        }
        tick()
    }

    private fun emitPlugEvent(connected: Boolean) {
        hostSink?.success(mapOf("type" to "plug", "connected" to connected))
    }

    private fun readPanels(): List<Map<String, Any>> {
        return displayManager.displays.map { display ->
            val (width, height) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Pair(display.mode.physicalWidth, display.mode.physicalHeight)
            } else {
                @Suppress("DEPRECATION")
                Pair(display.width, display.height)
            }
            mapOf(
                "id" to display.displayId,
                "title" to display.name,
                "width" to width,
                "height" to height,
                "rotation" to display.rotation,
                "primary" to (display.displayId == Display.DEFAULT_DISPLAY)
            )
        }
    }

    private fun resolution(panelId: Int, display: Display): Map<String, Any> {
        val (width, height) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Pair(display.mode.physicalWidth, display.mode.physicalHeight)
        } else {
            @Suppress("DEPRECATION")
            Pair(display.width, display.height)
        }
        return mapOf("id" to panelId, "width" to width.toDouble(), "height" to height.toDouble())
    }
}

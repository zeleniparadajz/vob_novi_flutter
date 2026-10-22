package com.vodovodbd.vodovod_bd_flutter

import android.app.ActivityManager
import android.app.Application
import android.app.ApplicationExitInfo
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.Executors

class VodovodApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        NativeDiagnostics.install(this)
    }
}

object NativeDiagnostics {
    @Volatile private var metadata: Map<String, Any?> = emptyMap()

    @Suppress("DEPRECATION")
    fun install(context: Context) {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        metadata = mapOf("appVersion" to (info.versionName ?: "unknown"),
            "buildNumber" to if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong())
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                val event = JSONObject(metadata).apply {
                    put("eventId", UUID.randomUUID().toString())
                    put("time", System.currentTimeMillis())
                    put("operation", "Android neobradjeni izuzetak: ${error.javaClass.simpleName}")
                    put("details", ("Thread: ${thread.name}\n$error\n" +
                        error.stackTrace.take(80).joinToString("\n")).take(8000))
                }
                val directory = File(context.filesDir, "native-diagnostics").apply { mkdirs() }
                val target = File(directory, "${event.getString("eventId")}.json")
                val partial = File("${target.path}.part")
                FileOutputStream(partial).use { stream ->
                    stream.write(event.toString().toByteArray(Charsets.UTF_8))
                    stream.fd.sync()
                }
                partial.renameTo(target)
            } catch (_: Throwable) {
                // A full disk or OOM must not interfere with Android's crash handling.
            } finally {
                if (previous != null) previous.uncaughtException(thread, error)
                else {
                    android.os.Process.killProcess(android.os.Process.myPid())
                    kotlin.system.exitProcess(10)
                }
            }
        }
    }

    fun setContext(data: Map<String, Any?>) { metadata = data.toMap() }

    fun readReports(context: Context): List<Map<String, Any?>> {
        val reports = mutableListOf<Map<String, Any?>>()
        val files = File(context.filesDir, "native-diagnostics").listFiles() ?: emptyArray()
        for (file in files.take(40)) {
            try {
                val json = JSONObject(file.readText())
                reports.add(json.keys().asSequence().associateWith { json.opt(it).takeUnless { v -> v == JSONObject.NULL } })
            } catch (_: Exception) { /* Keep damaged files for inspection. */ }
        }
        if (Build.VERSION.SDK_INT >= 30) {
            val acknowledged = context.getSharedPreferences("diagnostics", Context.MODE_PRIVATE)
                .getStringSet("acknowledgedExits", emptySet()) ?: emptySet()
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            for (exit in manager.getHistoricalProcessExitReasons(context.packageName, 0, 32)) {
                if (exit.reason !in setOf(ApplicationExitInfo.REASON_ANR,
                        ApplicationExitInfo.REASON_CRASH, ApplicationExitInfo.REASON_CRASH_NATIVE)) continue
                val id = UUID.nameUUIDFromBytes(
                    "${context.packageName}:${exit.timestamp}:${exit.pid}:${exit.reason}".toByteArray()).toString()
                if (id in acknowledged) continue
                var details = "process=${exit.processName}, reason=${exit.reason}, status=${exit.status}, " +
                    "pssKb=${exit.pss}, rssKb=${exit.rss}\n${exit.description.orEmpty()}"
                // Native tombstones are binary protobufs, not UTF-8 text.
                if (exit.reason == ApplicationExitInfo.REASON_ANR) {
                    try {
                        exit.traceInputStream?.bufferedReader()?.use { reader ->
                            val chars = CharArray(7600)
                            val count = reader.read(chars)
                            if (count > 0) details += "\n" + String(chars, 0, count)
                        }
                    } catch (_: Exception) { /* The OS may have evicted the trace. */ }
                }
                reports.add(mapOf("eventId" to id, "time" to exit.timestamp,
                    "operation" to if (exit.reason == ApplicationExitInfo.REASON_ANR)
                        "Android ANR: aplikacija nije odgovarala" else "Android sistemski izvjestaj o rusenju",
                    "details" to details.take(8000),
                    // ExitInfo cannot reliably identify the app version/user at the time of a past crash.
                    "appVersion" to "unknown", "buildNumber" to 0, "userId" to null))
            }
        }
        return reports
    }

    fun acknowledge(context: Context, id: String) {
        require(UUID.fromString(id).toString() == id)
        val directory = File(context.filesDir, "native-diagnostics")
        File(directory, "$id.json").delete()
        File(directory, "$id.json.part").delete()
        val prefs = context.getSharedPreferences("diagnostics", Context.MODE_PRIVATE)
        val ids = (prefs.getStringSet("acknowledgedExits", emptySet()) ?: emptySet()).toMutableSet()
        ids.add(id)
        check(prefs.edit().putStringSet("acknowledgedExits", ids).commit())
    }
}

class DiagnosticBridge(context: Context, messenger: BinaryMessenger) {
    private val context = context.applicationContext
    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "com.vodovodbd/diagnostics")
    private val connectivity = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    @Volatile private var closed = false
    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            handler.post { if (!closed) channel.invokeMethod("networkAvailable", null) }
        }
    }
    private var registered = false

    init {
        channel.setMethodCallHandler { call, result ->
            executor.execute {
                try {
                    val response: Any? = when (call.method) {
                        "readReports" -> NativeDiagnostics.readReports(this.context)
                        "setContext" -> {
                            NativeDiagnostics.setContext(mapOf("userId" to call.argument<String>("userId"),
                                "appVersion" to call.argument<String>("appVersion"),
                                "buildNumber" to call.argument<Number>("buildNumber")))
                            null
                        }
                        "acknowledgeReport" -> {
                            NativeDiagnostics.acknowledge(this.context, call.argument<String>("eventId")!!)
                            null
                        }
                        else -> { handler.post { result.notImplemented() }; return@execute }
                    }
                    handler.post { result.success(response) }
                } catch (error: Exception) {
                    handler.post { result.error("diagnostics_failed", error.javaClass.simpleName, null) }
                }
            }
        }
        if (Build.VERSION.SDK_INT >= 24) {
            try {
                connectivity.registerDefaultNetworkCallback(callback)
                registered = true
            } catch (_: Exception) { /* Periodic and resume retries still work. */ }
        }
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        if (registered) connectivity.unregisterNetworkCallback(callback)
        executor.shutdown()
    }
}

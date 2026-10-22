package com.vodovodbd.vodovod_bd_flutter

import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class UpdateFileProvider : FileProvider()

class MainActivity : FlutterActivity() {
    private val updateExecutor = Executors.newSingleThreadExecutor()
    private var diagnostics: DiagnosticBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        diagnostics = DiagnosticBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.vodovodbd/app_update")
            .setMethodCallHandler { call, result ->
                if (call.method == "canInstall") {
                    result.success(Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls())
                    return@setMethodCallHandler
                }
                if (call.method != "validateApk" && call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val version = call.argument<Number>("versionCode")?.toLong()
                if (path == null || version == null) {
                    result.error("invalid_apk", "Nedostaju podaci za instalaciju.", null)
                    return@setMethodCallHandler
                }
                updateExecutor.execute {
                    try {
                        val file = validateApk(path, version)
                        runOnUiThread {
                            try {
                                if (call.method == "validateApk") {
                                    result.success(null)
                                } else {
                                    result.success(openInstaller(file))
                                }
                            } catch (error: Exception) {
                                result.error("install_failed", error.message, null)
                            }
                        }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("invalid_apk", error.message, null) }
                    }
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun validateApk(path: String, expectedVersion: Long): File {
        val file = File(path).canonicalFile
        val directory = File(cacheDir, "updates").canonicalFile
        require(file.parentFile == directory && file.isFile && file.length() > 0) {
            "Preuzeta instalacija nije dostupna. Preuzmite je ponovo."
        }
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES
                    else PackageManager.GET_SIGNATURES
        val archive = packageManager.getPackageArchiveInfo(file.path, flags)
            ?: throw IllegalArgumentException("Preuzeti fajl nije ispravan APK.")
        val installed = packageManager.getPackageInfo(packageName, flags)
        require(archive.packageName == packageName) { "APK pripada drugoj aplikaciji." }
        fun version(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28)
            info.longVersionCode else info.versionCode.toLong()
        require(version(archive) == expectedVersion && expectedVersion > version(installed)) {
            "Verzija APK-a ne odgovara objavljenoj novoj verziji."
        }
        val sameSigner = if (Build.VERSION.SDK_INT >= 28) {
            val current = installed.signingInfo
            val next = archive.signingInfo
            if (current == null || next == null) false
            else if (current.hasMultipleSigners() || next.hasMultipleSigners()) {
                current.apkContentsSigners.toSet() == next.apkContentsSigners.toSet()
            } else {
                next.signingCertificateHistory.toSet().containsAll(current.apkContentsSigners.toSet())
            }
        } else {
            installed.signatures?.toSet() == archive.signatures?.toSet() &&
                !installed.signatures.isNullOrEmpty()
        }
        require(sameSigner) { "APK nije potpisan ključem ove aplikacije." }
        return file
    }

    private fun openInstaller(file: File): String {
        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")))
            return "permission_required"
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
        startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            clipData = ClipData.newRawUri("APK", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
        return "installer_opened"
    }

    override fun onDestroy() {
        diagnostics?.close()
        updateExecutor.shutdown()
        super.onDestroy()
    }
}

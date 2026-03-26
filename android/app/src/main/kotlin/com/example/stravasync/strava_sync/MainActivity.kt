package com.mj.stravasync

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.FileInputStream
import java.io.FileNotFoundException

class MainActivity : FlutterActivity() {
    private val channelName = "com.mj.stravasync/fitfile"
    private var channel: MethodChannel? = null
    private val pendingPaths = mutableListOf<String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialOpenedFiles" -> {
                    result.success(pendingPaths.toList())
                    pendingPaths.clear()
                }
                else -> result.notImplemented()
            }
        }
        if (pendingPaths.isNotEmpty()) {
            val paths = pendingPaths.toList()
            pendingPaths.clear()
            paths.forEach { p ->
                channel?.invokeMethod("fileOpened", p)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        when (intent.action) {
            Intent.ACTION_SEND -> {
                val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                uri?.let { handleUri(it) }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                uris?.forEach { handleUri(it) }
            }
            Intent.ACTION_VIEW -> {
                intent.data?.let { handleUri(it) }
            }
        }
    }

    private fun handleUri(uri: Uri) {
        val path = copyUriToCache(uri) ?: return
        val ch = channel
        if (ch != null) {
            ch.invokeMethod("fileOpened", path)
        } else {
            pendingPaths.add(path)
        }
    }

    private fun copyUriToCache(uri: Uri): String? {
        return try {
            val nameGuess = uri.lastPathSegment?.substringAfterLast('/') ?: "shared.fit"
            val fileName = if (nameGuess.lowercase().endsWith(".fit")) nameGuess else "$nameGuess.fit"
            val outFile = File(cacheDir, fileName)
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(outFile).use { output ->
                    input.copyTo(output)
                }
            } ?: return null
            outFile.absolutePath
        } catch (e: FileNotFoundException) {
            val fallback = fallbackExternalPath(uri) ?: return null
            if (Build.VERSION.SDK_INT >= 30 && !Environment.isExternalStorageManager()) {
                runCatching {
                    val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                    intent.data = Uri.parse("package:$packageName")
                    startActivity(intent)
                }
                Toast.makeText(this, "请授予“所有文件访问权限”后重试", Toast.LENGTH_LONG).show()
                return null
            }
            return runCatching {
                FileInputStream(fallback).use { input ->
                    FileOutputStream(File(cacheDir, fallback.name)).use { output ->
                        input.copyTo(output)
                    }
                }
                File(cacheDir, fallback.name).absolutePath
            }.getOrNull()
        } catch (e: Exception) {
            null
        }
    }

    private fun fallbackExternalPath(uri: Uri): File? {
        if (uri.scheme != "content") return null
        val p = uri.path ?: return null
        val prefix = "/external/"
        if (!p.startsWith(prefix)) return null
        val tail = p.removePrefix(prefix)
        if (tail.isEmpty()) return null
        val base = Environment.getExternalStorageDirectory()
        return File(base, tail)
    }
}

package cc.merr.fileinfra

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "cc.merr.fileinfra/native"
    private val STORAGE_PERMISSION_CODE = 1001
    private val NOTIFY_PERMISSION_CODE = 1002
    private var nativeChannel: MethodChannel? = null
    private var clipboardRequestConsumed = false
    private val stoppedListener: (Int) -> Unit = { generation ->
        nativeChannel?.invokeMethod("serviceStopped", mapOf("generation" to generation))
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        clipboardRequestConsumed = false
        if (hasWindowFocus()) sendClipboardWhenFocused()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) sendClipboardWhenFocused()
    }

    private fun sendClipboardWhenFocused() {
        val request = intent ?: return
        if (request.action != DufsForegroundService.ACTION_SEND_CLIPBOARD) return
        // Consume before reading/network dispatch, so focus changes and activity
        // recreation never send the same notification request twice.
        request.action = null
        clipboardRequestConsumed = true
        val generation = request.getIntExtra("generation", -1)
        val token = request.getStringExtra("clipboardRequestToken")
        request.removeExtra("generation")
        request.removeExtra("clipboardRequestToken")
        if (!DufsForegroundService.isAuthorizedClipboardSend(generation, token)) return
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
        val clip = cm.primaryClip ?: return
        if (clip.itemCount == 0) return
        val text = clip.getItemAt(0).coerceToText(this)?.toString() ?: return
        if (text.isEmpty()) return
        startService(Intent(this, DufsForegroundService::class.java)
            .setAction(DufsForegroundService.ACTION_SEND_CLIPBOARD)
            .putExtra("generation", generation).putExtra("text", text))
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        if (savedInstanceState?.getBoolean("clipboardRequestConsumed", false) == true &&
            intent?.action == DufsForegroundService.ACTION_SEND_CLIPBOARD) {
            intent.action = null
            intent.removeExtra("generation")
            intent.removeExtra("clipboardRequestToken")
            clipboardRequestConsumed = true
        }
        super.onCreate(savedInstanceState)
        // API 33+ 的通知运行权限要在前台服务常驻通知显示前拿到。
        // 只挂在 requestStorage 通道上不够：存量用户存储权限早已授予，
        // 那条路径不会再走，通知会被静默压制（只能靠系统"渠道创建后
        // 自动弹一次"的兜底，时机不可控）。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFY_PERMISSION_CODE
            )
        }
    }

    override fun onSaveInstanceState(outState: android.os.Bundle) {
        super.onSaveInstanceState(outState)
        outState.putBoolean("clipboardRequestConsumed", clipboardRequestConsumed)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        nativeChannel = channel
        DufsForegroundService.stoppedListener = stoppedListener

        channel.setMethodCallHandler { call, result ->
            // 顶层兜底：handler 抛出的任何异常以 result.error 回到 Dart，
            /// 否则 Dart 只能收到泛化的 channel 错误（如 FGS 后台启动限制
            /// 的 ForegroundServiceStartNotAllowedException）。
            try {
                handleMethodCall(call, result)
            } catch (e: Exception) {
                Log.e("fileinfra", "method ${call.method} failed", e)
                result.error("native_error", "${e.javaClass.simpleName}: ${e.message}", null)
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (DufsForegroundService.stoppedListener === stoppedListener) {
            DufsForegroundService.stoppedListener = null
            // The tools HTTP listener belongs to this engine, not the native
            // foreground service that can remain alive after task removal.
            DufsForegroundService.updateAddress(this, DufsForegroundService.currentAddress, "")
        }
        nativeChannel?.setMethodCallHandler(null)
        nativeChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handleMethodCall(call: io.flutter.plugin.common.MethodCall, result: io.flutter.plugin.common.MethodChannel.Result) {
        when (call.method) {
                "log" -> {
                    val msg = call.argument<String>("msg") ?: ""
                    Log.d("fileinfra", msg)
                    result.success(null)
                }
                "getNativeLibraryDir" -> {
                    result.success(applicationInfo.nativeLibraryDir)
                }
                "isStorageGranted" -> {
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        Environment.isExternalStorageManager()
                    } else {
                        ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
                    }
                    Log.d("fileinfra", "Storage granted: $granted (API ${Build.VERSION.SDK_INT})")
                    result.success(granted)
                }
                "requestStorage" -> {
                    // API 33+ FGS 通知需要 POST_NOTIFICATIONS 运行时授权，
                    // 否则服务常驻通知被系统静默隐藏。
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            NOTIFY_PERMISSION_CODE
                        )
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                            intent.data = Uri.parse("package:${packageName}")
                            startActivity(intent)
                        } catch (e: Exception) {
                            startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                        }
                    } else {
                        ActivityCompat.requestPermissions(this, arrayOf(
                            Manifest.permission.READ_EXTERNAL_STORAGE,
                            Manifest.permission.WRITE_EXTERNAL_STORAGE
                        ), STORAGE_PERMISSION_CODE)
                    }
                    result.success(true)
                }
                "startForegroundService" -> {
                    val port = call.argument<Int>("port") ?: 0
                    val path = call.argument<String>("path") ?: ""
                    val args = call.argument<List<String>>("args")?.toTypedArray() ?: emptyArray()
                    val lang = call.argument<String>("lang") ?: "en"
                    val address = call.argument<String>("address") ?: ""
                    if (port !in 1..65535 || path.isEmpty()) {
                        result.error("invalid_args", "port=$port path-empty=${path.isEmpty()}", null)
                        return
                    }
                    val intent = Intent(this, DufsForegroundService::class.java)
                    intent.putExtra("port", port)
                    intent.putExtra("path", path)
                    intent.putExtra("args", args)
                    intent.putExtra("lang", lang)
                    intent.putExtra("address", address)
                    intent.putExtra("notifClipboard", call.argument<Boolean>("notifClipboard") ?: true)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    Log.d("fileinfra", "Foreground service start requested: port=$port")
                    result.success(true)
                }
                "updateNotificationAddress" -> {
                    val address = call.argument<String>("address") ?: ""
                    val clipboardAddress = call.argument<String>("clipboardAddress") ?: ""
                    DufsForegroundService.updateAddress(this, address, clipboardAddress, call.argument<Int>("generation"))
                    result.success(true)
                }
                "updateNotificationClipboard" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    DufsForegroundService.updateClipboardButtons(this, enabled)
                    result.success(true)
                }
                "stopForegroundService" -> {
                    DufsForegroundService.requestStop(this, call.argument<Int>("generation"))
                    Log.d("fileinfra", "Foreground service stop requested")
                    result.success(true)
                }
                "isServiceRunning" -> {
                    result.success(DufsForegroundService.isRunning)
                }
                // 点击传输记录打开本地文件。不走 open_filex：它在 Android 13+
                // 会先索要 READ_MEDIA_IMAGES/VIDEO/AUDIO，而它实际是用
                // FileProvider + grantUriPermissions 把文件递出去的，那三个
                // 媒体权限对本应用是多余的（F-Droid 会按 NEW_PERMISSIONS
                // 反特性标记）。清单里已 tools:node="remove" 剥掉。
                "openFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    if (path.isEmpty()) {
                        result.error("invalid_args", "path empty", null)
                        return
                    }
                    result.success(openWithSystemViewer(File(path)))
                }
                "getServiceInfo" -> {
                    val info = hashMapOf<String, Any>(
                        "isRunning" to DufsForegroundService.isRunning,
                        "port" to DufsForegroundService.currentPort,
                        "path" to DufsForegroundService.currentPath,
                        "address" to DufsForegroundService.currentAddress,
                        "clipboardAddress" to DufsForegroundService.currentClipboardAddress,
                        "generation" to DufsForegroundService.startGeneration,
                        "error" to (DufsForegroundService.lastError ?: "")
                    )
                    result.success(info)
                }
                else -> result.notImplemented()
            }
    }

    /// 返回 done / notFound / isDir / noApp / error:<msg>，由 Dart 侧映射文案。
    private fun openWithSystemViewer(file: File): String {
        if (!file.exists()) return "notFound"
        if (file.isDirectory) return "isDir"
        val mime = guessMimeType(file.name)
            ?: "application/octet-stream"
        // minSdk = 24（Flutter 默认）已经 ≥ N，FileProvider 总是可用；
        // 没有写 file:// 回退分支的必要（24+ 上递 file:// URI 会直接
        // FileUriExposedException）。
        val uri = try {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        } catch (e: IllegalArgumentException) {
            // 不在 file_paths.xml 覆盖范围内（root-path 已覆盖全盘，
            // 真走到这里说明路径本身有问题）
            return "error:${e.javaClass.simpleName}"
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addCategory(Intent.CATEGORY_DEFAULT)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            // APK 走系统安装器，必须 NEW_TASK；其余用 SINGLE_TOP，
            // 与 open_filex 原有行为一致。
            addFlags(
                if (mime == "application/vnd.android.package-archive") {
                    Intent.FLAG_ACTIVITY_NEW_TASK
                } else {
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
            )
        }
        return try {
            startActivity(intent)
            "done"
        } catch (e: ActivityNotFoundException) {
            "noApp"
        } catch (e: Exception) {
            "error:${e.javaClass.simpleName}"
        }
    }

    private fun guessMimeType(name: String): String? {
        val ext = name.substringAfterLast('.', "").lowercase()
        if (ext.isEmpty()) return null
        if (ext == "apk") return "application/vnd.android.package-archive"
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
    }

    /// Dart 侧不等待授权结果（settings 页/启动流程都会重新查
    /// isStorageGranted），这里只做日志兜底，防止系统回调缺实现被吞。
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        Log.d("fileinfra", "permission result code=$requestCode granted=$granted")
    }
}

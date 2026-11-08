package cc.merr.fileinfra

import android.app.Application
import android.app.Notification
import android.app.Service
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Looper
import java.net.ServerSocket
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29], application = Application::class)
class NotificationContractTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val prefs get() = context.getSharedPreferences("fileinfra_native", Context.MODE_PRIVATE)

    @Before fun prepare() {
        prefs.edit().clear().commit()
        prefs.edit().putInt("port", 5000).putString("path", "/tmp/share")
            .putString("args", "[\"-p\",\"5000\",\"/tmp/share\"]")
            .putString("lang", "en").putString("address", "http://192.168.1.5:5000")
            .putString("clipboardAddress", "http://192.168.1.5:7000")
            .putBoolean("notifClipboard", false).commit()
        setState("isRunning", true)
        setState("currentPort", 5000)
        setState("currentPath", "/tmp/share")
        setState("currentAddress", "http://192.168.1.5:5000")
        setState("currentClipboardAddress", "")
        setState("lastError", null)
    }

    @After fun reset() {
        DufsForegroundService.stoppedListener = null
        setState("isRunning", false)
        setState("currentPort", 0)
        setState("currentClipboardAddress", "")
        prefs.edit().clear().commit()
    }

    private fun setState(name: String, value: Any?) {
        DufsForegroundService::class.java.getDeclaredField(name).apply {
            isAccessible = true
            set(null, value)
        }
    }

    @Test fun tileRestartPreservesDisabledClipboardButtons() {
        val launch = DufsForegroundService.readLastLaunch(context)!!
        assertFalse(launch.getBooleanExtra("notifClipboard", true))
    }

    @Test fun tileRestartDoesNotAdvertiseAnAbsentDartToolsServer() {
        val launch = DufsForegroundService.readLastLaunch(context)!!
        val notification = DufsForegroundService.buildNotification(
            context, 5000, launch.getStringExtra("address")!!,
            launch.getStringExtra("clipboardAddress") ?: "", "/tmp/share", "en", true,
        )
        assertEquals(1, notification.actions.size)
        assertFalse(notification.extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?.contains("7000") == true)
    }

    @Test fun addressUpdatesKeepTheEndpointUsedByPullAndSettings() {
        DufsForegroundService.updateAddress(context, "http://192.168.1.5:5000", "http://192.168.1.5:7001")
        assertEquals("http://192.168.1.5:7001", DufsForegroundService.currentClipboardAddress)
        DufsForegroundService.updateClipboardButtons(context, true)
        val notification = shadowOf(context.getSystemService(android.app.NotificationManager::class.java))
            .getNotification(1001)
        assertEquals(3, notification.actions.size)
    }

    @Test fun sendOpensTheActivityDirectlyForFocusedClipboardAccess() {
        val notification = DufsForegroundService.buildNotification(
            context, 5000, "http://192.168.1.5:5000", "http://192.168.1.5:7000",
            "/tmp/share", "en", true,
        )
        val send = shadowOf(notification.actions[1].actionIntent)
        assertTrue(send.isActivityIntent)
        assertEquals(MainActivity::class.java.name, send.savedIntent.component!!.className)
        assertEquals(DufsForegroundService.ACTION_SEND_CLIPBOARD, send.savedIntent.action)
    }

    @Test fun flutterStartPreservesTheUsersNotificationPreference() {
        val activity = Robolectric.buildActivity(MainActivity::class.java).get()
        val method = MainActivity::class.java.getDeclaredMethod(
            "handleMethodCall", MethodCall::class.java, MethodChannel.Result::class.java,
        ).apply { isAccessible = true }
        val result = object : MethodChannel.Result {
            override fun success(result: Any?) {}
            override fun error(code: String, message: String?, details: Any?) = fail("$code: $message")
            override fun notImplemented() = fail("not implemented")
        }
        method.invoke(activity, MethodCall("startForegroundService", mapOf(
            "port" to 5000, "path" to "/tmp/share", "args" to listOf("/tmp/share"),
            "lang" to "en", "address" to "", "notifClipboard" to false,
        )), result)
        val intent = shadowOf(RuntimeEnvironment.getApplication()).nextStartedService
        assertFalse(intent.getBooleanExtra("notifClipboard", true))
    }

    @Test fun delayedStopIntentDoesNotKillTheNewRun() {
        val service = Robolectric.buildService(DufsForegroundService::class.java).create().get()
        setState("startGeneration", 10)
        service.onStartCommand(Intent(context, DufsForegroundService::class.java)
            .setAction(DufsForegroundService.ACTION_STOP).putExtra("generation", 9), 0, 2)
        assertTrue(DufsForegroundService.isRunning)
        assertEquals(10, DufsForegroundService.startGeneration)
    }

    @Test fun duplicateStopWithNoActiveRunSatisfiesTheForegroundContractAndStops() {
        val service = Robolectric.buildService(DufsForegroundService::class.java).create().get()
        setState("isRunning", false)
        setState("startGeneration", 12)
        val result = service.onStartCommand(Intent(context, DufsForegroundService::class.java)
            .setAction(DufsForegroundService.ACTION_STOP).putExtra("generation", 11), 0, 2)
        assertEquals(1001, shadowOf(service).lastForegroundNotificationId)
        assertTrue(shadowOf(service).isStoppedBySelf)
        assertEquals(Service.START_NOT_STICKY, result)
    }

    @Test fun delayedStopKeepsANewerStartupAndItsForegroundNotification() {
        val service = Robolectric.buildService(DufsForegroundService::class.java).create().get()
        setState("isRunning", false)
        setState("startGeneration", 14)
        DufsForegroundService::class.java.getDeclaredField("startingGeneration")
            .apply { isAccessible = true }.set(service, 14)
        val notification = DufsForegroundService.buildNotification(
            context, 5000, "http://192.168.1.5:5000", "", "/tmp/share", "en", true,
        )
        service.startForeground(1001, notification)
        service.onStartCommand(Intent(context, DufsForegroundService::class.java)
            .setAction(DufsForegroundService.ACTION_STOP).putExtra("generation", 13), 0, 2)
        assertFalse(shadowOf(service).isStoppedBySelf)
        assertTrue(shadowOf(service).isLastForegroundNotificationAttached)
        assertEquals(14, DufsForegroundService.startGeneration)
        service.onDestroy()
    }

    @Test fun sendWaitsForFocusAndCapturesTextOnce() {
        setState("startGeneration", 20)
        val notification = DufsForegroundService.buildNotification(
            context, 5000, "http://192.168.1.5:5000", "http://192.168.1.5:7000",
            "/tmp/share", "en", true,
        )
        val activity = Robolectric.buildActivity(MainActivity::class.java).get()
        activity.intent = shadowOf(notification.actions[1].actionIntent).savedIntent
        (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
            .setPrimaryClip(ClipData.newPlainText("test", "captured while focused"))
        val application = shadowOf(RuntimeEnvironment.getApplication())
        activity.onWindowFocusChanged(false)
        assertNull(application.nextStartedService)
        activity.onWindowFocusChanged(true)
        val sent = application.nextStartedService
        assertNotNull(sent)
        assertEquals("captured while focused", sent.getStringExtra("text"))
        assertEquals(20, sent.getIntExtra("generation", -1))
        activity.onWindowFocusChanged(false)
        activity.onWindowFocusChanged(true)
        assertNull(application.nextStartedService)
    }

    @Test fun aConsumedSendRequestIsSavedAcrossActivityRecreation() {
        setState("startGeneration", 21)
        val notification = DufsForegroundService.buildNotification(
            context, 5000, "http://192.168.1.5:5000", "http://192.168.1.5:7000",
            "/tmp/share", "en", true,
        )
        val activity = Robolectric.buildActivity(MainActivity::class.java).get()
        activity.intent = Intent(shadowOf(notification.actions[1].actionIntent).savedIntent)
        (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
            .setPrimaryClip(ClipData.newPlainText("test", "once"))
        activity.onWindowFocusChanged(true)
        assertNotNull(shadowOf(RuntimeEnvironment.getApplication()).nextStartedService)
        val state = Bundle()
        io.flutter.embedding.android.FlutterActivity::class.java.getDeclaredMethod("onSaveInstanceState", Bundle::class.java)
            .apply { isAccessible = true }.invoke(activity, state)
        assertTrue(state.getBoolean("clipboardRequestConsumed", false))
    }

    @Test fun anOldSendRequestCannotSendIntoANewShare() {
        setState("startGeneration", 30)
        val activity = Robolectric.buildActivity(MainActivity::class.java).get()
        activity.intent = Intent(context, MainActivity::class.java)
            .setAction(DufsForegroundService.ACTION_SEND_CLIPBOARD).putExtra("generation", 29)
        (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
            .setPrimaryClip(ClipData.newPlainText("test", "old request"))
        activity.onWindowFocusChanged(true)
        assertNull(shadowOf(RuntimeEnvironment.getApplication()).nextStartedService)
        assertNull(activity.intent.action)
    }

    @Test fun systemRedeliveryAfterAClipboardActionRestoresTheNativeLaunch() {
        val service = Robolectric.buildService(DufsForegroundService::class.java).create().get()
        setState("isRunning", false)
        service.onStartCommand(Intent(context, DufsForegroundService::class.java)
            .setAction(DufsForegroundService.ACTION_SEND_CLIPBOARD)
            .putExtra("generation", 10).putExtra("text", "must not replay"),
            Service.START_FLAG_REDELIVERY, 3)
        val notification = shadowOf(service).lastForegroundNotification
        assertNotNull(notification)
        assertTrue(notification.extras.getCharSequence(Notification.EXTRA_TEXT)
            ?.contains("192.168.1.5:5000") == true)
        service.onDestroy()
    }

    @Test fun sendPostsTheCapturedTextRatherThanReadingTheBackgroundClipboard() {
        val service = Robolectric.buildService(DufsForegroundService::class.java).create().get()
        val executor = Executors.newSingleThreadExecutor()
        ServerSocket(0).use { server ->
            server.soTimeout = 3000
            val received = executor.submit<String> {
                server.accept().use { socket ->
                    socket.soTimeout = 3000
                    val reader = socket.getInputStream().bufferedReader()
                    var length = 0
                    while (true) {
                        val line = reader.readLine() ?: break
                        if (line.isEmpty()) break
                        if (line.startsWith("Content-Length:", ignoreCase = true)) {
                            length = line.substringAfter(':').trim().toInt()
                        }
                    }
                    val body = CharArray(length)
                    var position = 0
                    while (position < length) {
                        val count = reader.read(body, position, length - position)
                        if (count < 0) break
                        position += count
                    }
                    socket.getOutputStream().write("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray())
                    String(body, 0, position)
                }
            }
            setState("startGeneration", 40)
            setState("currentClipboardAddress", "http://192.168.1.5:${server.localPort}")
            (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
                .setPrimaryClip(ClipData.newPlainText("test", "changed after capture"))
            service.onStartCommand(Intent(context, DufsForegroundService::class.java)
                .setAction(DufsForegroundService.ACTION_SEND_CLIPBOARD)
                .putExtra("generation", 40).putExtra("text", "captured text\nsecond line"), 0, 4)
            try {
                assertEquals("captured text\nsecond line", received.get(4, TimeUnit.SECONDS))
            } finally {
                executor.shutdownNow()
                service.onDestroy()
            }
        }
    }

    @Test fun anExternalStyleSendIntentCannotPublishTheClipboard() {
        setState("startGeneration", 70)
        val activity = Robolectric.buildActivity(MainActivity::class.java).get()
        activity.intent = Intent(context, MainActivity::class.java)
            .setAction(DufsForegroundService.ACTION_SEND_CLIPBOARD).putExtra("generation", 70)
        (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
            .setPrimaryClip(ClipData.newPlainText("test", "private clipboard"))
        activity.onWindowFocusChanged(true)
        assertNull(shadowOf(RuntimeEnvironment.getApplication()).nextStartedService)
    }

    @Test fun disablingButtonsRevokesAnExistingSendRequest() {
        setState("startGeneration", 71)
        setState("currentClipboardAddress", "http://192.168.1.5:7000")
        val notification = DufsForegroundService.buildNotification(
            context, 5000, "http://192.168.1.5:5000", "http://192.168.1.5:7000", "/tmp/share", "en", true,
        )
        val oldRequest = Intent(shadowOf(notification.actions[1].actionIntent).savedIntent)
        DufsForegroundService.updateClipboardButtons(context, false)
        val activity = Robolectric.buildActivity(MainActivity::class.java).get()
        activity.intent = oldRequest
        (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
            .setPrimaryClip(ClipData.newPlainText("test", "revoked clipboard"))
        activity.onWindowFocusChanged(true)
        assertNull(shadowOf(RuntimeEnvironment.getApplication()).nextStartedService)
    }

    @Test fun aLateOldChildCannotReplaceTheProcessThatStopMustKill() {
        val service = Robolectric.buildService(DufsForegroundService::class.java).create().get()
        val old = ControlledProcess()
        val current = ControlledProcess()
        val claim = DufsForegroundService::class.java.getDeclaredMethod("claimChild", Process::class.java, Int::class.javaPrimitiveType)
            .apply { isAccessible = true }
        setState("startGeneration", 80)
        claim.invoke(service, old, 80)
        setState("startGeneration", 81)
        claim.invoke(service, current, 81)
        claim.invoke(service, old, 80)
        service.onStartCommand(Intent(context, DufsForegroundService::class.java)
            .setAction(DufsForegroundService.ACTION_STOP).putExtra("generation", 81), 0, 1)
        assertFalse("Stop must kill the current child after an old spawn finishes late", current.alive)
        assertFalse("The superseded child must also be killed", old.alive)
    }

    @Test fun aStaleStartupErrorCannotPoisonTheCurrentGeneration() {
        val service = Robolectric.buildService(DufsForegroundService::class.java).create().get()
        setState("startGeneration", 83)
        DufsForegroundService::class.java.getDeclaredMethod("publishStartError", Int::class.javaPrimitiveType, String::class.java)
            .apply { isAccessible = true }.invoke(service, 82, "old spawn failed")
        assertNull(DufsForegroundService.lastError)
        DufsForegroundService::class.java.getDeclaredMethod("publishStartError", Int::class.javaPrimitiveType, String::class.java)
            .apply { isAccessible = true }.invoke(service, 83, "current spawn failed")
        assertEquals("current spawn failed", DufsForegroundService.lastError)
    }

    @Test fun notificationRebuildRotatesSendAuthorizationAndKeepsTheNewActionUsable() {
        setState("startGeneration", 90)
        val first = DufsForegroundService.buildNotification(
            context, 5000, "http://192.168.1.5:5000", "http://192.168.1.5:7000", "/tmp/share", "en", true,
        )
        val oldRequest = Intent(shadowOf(first.actions[1].actionIntent).savedIntent)
        val second = DufsForegroundService.buildNotification(
            context, 5000, "http://192.168.1.6:5000", "http://192.168.1.6:7000", "/tmp/share", "en", true,
        )
        val newRequest = Intent(shadowOf(second.actions[1].actionIntent).savedIntent)
        assertNotEquals(oldRequest.getStringExtra("clipboardRequestToken"), newRequest.getStringExtra("clipboardRequestToken"))
        val activity = Robolectric.buildActivity(MainActivity::class.java).get()
        (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
            .setPrimaryClip(ClipData.newPlainText("test", "fresh action"))
        activity.intent = oldRequest
        activity.onWindowFocusChanged(true)
        assertNull(shadowOf(RuntimeEnvironment.getApplication()).nextStartedService)
        activity.intent = newRequest
        activity.onWindowFocusChanged(true)
        assertEquals("fresh action", shadowOf(RuntimeEnvironment.getApplication()).nextStartedService.getStringExtra("text"))
    }

    @Test fun oldChildFailureCannotReleaseTheCurrentChildHandle() {
        val service = Robolectric.buildService(DufsForegroundService::class.java).create().get()
        val old = ControlledProcess()
        val current = ControlledProcess()
        setState("startGeneration", 92)
        DufsForegroundService::class.java.getDeclaredMethod("claimChild", Process::class.java, Int::class.javaPrimitiveType)
            .apply { isAccessible = true }.invoke(service, current, 92)
        DufsForegroundService::class.java.getDeclaredMethod("releaseChild", Process::class.java)
            .apply { isAccessible = true }.invoke(service, old)
        service.onStartCommand(Intent(context, DufsForegroundService::class.java)
            .setAction(DufsForegroundService.ACTION_STOP).putExtra("generation", 92), 0, 1)
        assertFalse(current.alive)
    }

    @Test fun unexpectedChildExitStopsTheNotificationAndNotifiesDartForThatRun() {
        val service = Robolectric.buildService(DufsForegroundService::class.java).create().get()
        val child = ControlledProcess()
        setState("startGeneration", 100)
        setState("runningGeneration", 100)
        var stoppedGeneration: Int? = null
        DufsForegroundService.stoppedListener = { stoppedGeneration = it }
        DufsForegroundService::class.java.getDeclaredMethod("claimChild", Process::class.java, Int::class.javaPrimitiveType)
            .apply { isAccessible = true }.invoke(service, child, 100)
        service.startForeground(1001, DufsForegroundService.buildNotification(
            context, 5000, "http://192.168.1.5:5000", "http://192.168.1.5:7000", "/tmp/share", "en", true,
        ))
        val watcher = watch(service, child, 100)
        child.destroy()
        watcher.join(2000)
        assertFalse(watcher.isAlive)
        shadowOf(Looper.getMainLooper()).idle()
        assertFalse("an exited file child must stop the native run", DufsForegroundService.isRunning)
        assertTrue(shadowOf(service).isStoppedBySelf)
        assertFalse(shadowOf(service).isLastForegroundNotificationAttached)
        assertEquals(100, stoppedGeneration)
        assertEquals("", DufsForegroundService.currentClipboardAddress)
        assertTrue(DufsForegroundService.lastError?.contains("exited unexpectedly") == true)
        DufsForegroundService.stoppedListener = null
    }

    @Test fun anOldChildExitCannotStopTheReplacementRun() {
        val service = Robolectric.buildService(DufsForegroundService::class.java).create().get()
        val old = ControlledProcess()
        val current = ControlledProcess()
        setState("startGeneration", 102)
        val watcher = watch(service, old, 101)
        DufsForegroundService::class.java.getDeclaredMethod("claimChild", Process::class.java, Int::class.javaPrimitiveType)
            .apply { isAccessible = true }.invoke(service, current, 102)
        old.destroy()
        watcher.join(2000)
        assertFalse(watcher.isAlive)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(DufsForegroundService.isRunning)
        assertTrue(current.alive)
        assertNull(DufsForegroundService.lastError)
        service.onDestroy()
    }

    @Test fun intentionalStopDoesNotBecomeAnUnexpectedExitError() {
        val service = Robolectric.buildService(DufsForegroundService::class.java).create().get()
        val child = ControlledProcess()
        setState("startGeneration", 104)
        DufsForegroundService::class.java.getDeclaredMethod("claimChild", Process::class.java, Int::class.javaPrimitiveType)
            .apply { isAccessible = true }.invoke(service, child, 104)
        val watcher = watch(service, child, 104)
        service.onStartCommand(Intent(context, DufsForegroundService::class.java)
            .setAction(DufsForegroundService.ACTION_STOP).putExtra("generation", 104), 0, 1)
        watcher.join(2000)
        assertFalse(watcher.isAlive)
        shadowOf(Looper.getMainLooper()).idle()
        assertFalse(DufsForegroundService.isRunning)
        assertNull(DufsForegroundService.lastError)
    }

    private fun watch(service: DufsForegroundService, proc: Process, generation: Int): Thread =
        DufsForegroundService::class.java.getDeclaredMethod("watchChild", Process::class.java, Int::class.javaPrimitiveType)
            .apply { isAccessible = true }.invoke(service, proc, generation)
            as Thread

    private class ControlledProcess : Process() {
        private val exited = java.util.concurrent.CountDownLatch(1)
        @Volatile
        var alive = true
            private set
        override fun getOutputStream() = ByteArrayOutputStream()
        override fun getInputStream() = ByteArrayInputStream(byteArrayOf())
        override fun getErrorStream() = ByteArrayInputStream(byteArrayOf())
        override fun waitFor(): Int { exited.await(); return exitValue() }
        override fun exitValue(): Int {
            if (alive) throw IllegalThreadStateException("child is alive")
            return 0
        }
        override fun destroy() { alive = false; exited.countDown() }
        override fun destroyForcibly(): Process { destroy(); return this }
    }
}

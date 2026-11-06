package com.bcapp.frontend

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject

/**
 * Push for PushService (lib/services/push_service.dart), channel "bcapp/push".
 * Firebase is on only when android/app/google-services.json was there at build
 * time; otherwise getToken answers null and the app keeps in-app alerts only.
 * Tapping a push starts this activity with the message data as extras.
 */
class MainActivity : FlutterActivity() {
    companion object {
        @Volatile
        var activeChannel: MethodChannel? = null
    }

    private var channel: MethodChannel? = null
    private var openedConversation: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        openedConversation = intent?.getStringExtra("conversation_id")
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bcapp/push").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getToken" ->
                        if (FirebaseApp.getApps(this@MainActivity).isEmpty()) {
                            result.success(null)
                        } else {
                            FirebaseMessaging.getInstance().token
                                .addOnSuccessListener { result.success(it) }
                                .addOnFailureListener { result.success(null) }
                        }
                    "takeOpenedConversation" -> {
                        result.success(openedConversation)
                        openedConversation = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
        activeChannel = channel
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (activeChannel === channel) {
            activeChannel = null
        }
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val id = intent.getStringExtra("conversation_id") ?: return
        channel?.invokeMethod("openConversation", id)
    }
}

/**
 * Receives FCM token rotations even when the app is closed and syncs the new
 * token to the backend (/api/devices) immediately without waiting for the next
 * app launch. When the Flutter engine is alive, forwards onNewToken over
 * MethodChannel("bcapp/push") as well.
 */
class BcPushService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        if (token.isEmpty()) return
        val ch = MainActivity.activeChannel
        if (ch != null) {
            Handler(Looper.getMainLooper()).post {
                ch.invokeMethod("onNewToken", token)
            }
            return
        }
        val appContext = applicationContext
        Thread {
            sendTokenToBackend(appContext, token)
        }.start()
    }

    private fun sendTokenToBackend(context: Context, token: String) {
        try {
            val prefs = context.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE
            )
            val jwt = prefs.getString("flutter.bcapp_jwt_token", null)
            val deviceId = prefs.getString("flutter.bcapp_device_id", null)
            if (jwt.isNullOrEmpty() || deviceId.isNullOrEmpty()) return
            val apiBase = prefs.getString("flutter.bcapp_api_base", "http://127.0.0.1:8095")
                ?: "http://127.0.0.1:8095"
            val popup = prefs.getBoolean("flutter.bcapp_alert_popup", true)
            val sound = prefs.getBoolean("flutter.bcapp_alert_sound", true)
            val sounds = JSONObject()
                .put("normal", prefs.getString("flutter.bcapp_alert_sound_normal", "ting") ?: "ting")
                .put("urgent", prefs.getString("flutter.bcapp_alert_sound_urgent", "urgent") ?: "urgent")
                .put("ai", prefs.getString("flutter.bcapp_alert_sound_ai", "robot") ?: "robot")
            val body = JSONObject()
                .put("device_id", deviceId)
                .put("token", token)
                .put("platform", "android")
                .put("popup", popup)
                .put("sound", sound)
                .put("sounds", sounds)
                .toString()
                .toByteArray(Charsets.UTF_8)

            val conn = (URL("$apiBase/api/devices").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 5000
                readTimeout = 5000
                doOutput = true
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
                setRequestProperty("Authorization", "Bearer $jwt")
            }
            conn.outputStream.use { it.write(body) }
            conn.responseCode
            conn.disconnect()
        } catch (_: Exception) {
        }
    }
}

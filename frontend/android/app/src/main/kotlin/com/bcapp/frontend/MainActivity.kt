package com.bcapp.frontend

import android.content.Intent
import android.os.Bundle
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Push for PushService (lib/services/push_service.dart), channel "bcapp/push".
 * Firebase is on only when android/app/google-services.json was there at build
 * time; otherwise getToken answers null and the app keeps in-app alerts only.
 * Tapping a push starts this activity with the message data as extras.
 */
class MainActivity : FlutterActivity() {
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
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val id = intent.getStringExtra("conversation_id") ?: return
        channel?.invokeMethod("openConversation", id)
    }
}

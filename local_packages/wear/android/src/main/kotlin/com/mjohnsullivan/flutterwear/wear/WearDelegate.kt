package com.mjohnsullivan.flutterwear.wear

import android.app.Activity
import android.os.Bundle
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleObserver
import androidx.lifecycle.OnLifecycleEvent
import com.google.android.wearable.compat.WearableActivityController
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.lifecycle.HiddenLifecycleReference
import io.flutter.plugin.common.MethodChannel

// This class is only loaded on Wear OS devices (controlled by WearPlugin.mIsWearOs).
// Keeping all WearableActivityController references here prevents ClassNotFoundException
// when this plugin is loaded on a regular Android phone.
class WearDelegate(
    private val binding: ActivityPluginBinding,
    private val channel: MethodChannel?,
) : LifecycleObserver {

    val activity: Activity get() = binding.activity

    private val ambientCallback = object : WearableActivityController.AmbientCallback() {
        override fun onEnterAmbient(ambientDetails: Bundle) {
            channel?.invokeMethod(
                "onEnterAmbient",
                mapOf(
                    "burnInProtection" to ambientDetails.getBoolean(WearableActivityController.EXTRA_BURN_IN_PROTECTION, false),
                    "lowBitAmbient" to ambientDetails.getBoolean(WearableActivityController.EXTRA_LOWBIT_AMBIENT, false),
                ),
            )
        }

        override fun onExitAmbient() {
            channel?.invokeMethod("onExitAmbient", null)
        }

        override fun onUpdateAmbient() {
            channel?.invokeMethod("onUpdateAmbient", null)
        }

        override fun onInvalidateAmbientOffload() {
            channel?.invokeMethod("onInvalidateAmbientOffload", null)
        }
    }

    private val controller = WearableActivityController(
        "WearPlugin",
        binding.activity,
        ambientCallback,
    ).also { it.setAmbientEnabled() }

    val isAmbient: Boolean get() = controller.isAmbient

    fun setAutoResumeEnabled(enabled: Boolean) = controller.setAutoResumeEnabled(enabled)
    fun setAmbientOffloadEnabled(enabled: Boolean) = controller.setAmbientOffloadEnabled(enabled)

    fun detach() {
        val ref = binding.lifecycle as HiddenLifecycleReference
        ref.lifecycle.removeObserver(this)
    }

    @OnLifecycleEvent(Lifecycle.Event.ON_CREATE)
    fun onCreate() = controller.onCreate()

    @OnLifecycleEvent(Lifecycle.Event.ON_RESUME)
    fun onResume() = controller.onResume()

    @OnLifecycleEvent(Lifecycle.Event.ON_PAUSE)
    fun onPause() = controller.onPause()

    @OnLifecycleEvent(Lifecycle.Event.ON_STOP)
    fun onStop() = controller.onStop()

    @OnLifecycleEvent(Lifecycle.Event.ON_DESTROY)
    fun onDestroy() = controller.onDestroy()
}

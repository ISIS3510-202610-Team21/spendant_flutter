package com.mjohnsullivan.flutterwear.wear

import android.content.pm.PackageManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.lifecycle.HiddenLifecycleReference
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

// WearDelegate (which references Wear OS classes) is only loaded on actual Wear OS devices.
// On phones, the delegate is never instantiated so WearableActivityController is never resolved,
// avoiding the NoClassDefFoundError that occurs in WorkManager background contexts.
class WearPlugin : FlutterPlugin, ActivityAware, MethodCallHandler {
    private var mMethodChannel: MethodChannel? = null
    private var mDelegate: WearDelegate? = null
    private var mIsWearOs = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        mIsWearOs = binding.applicationContext.packageManager
            .hasSystemFeature(PackageManager.FEATURE_WATCH)
        mMethodChannel = MethodChannel(binding.binaryMessenger, "wear")
        mMethodChannel!!.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        mMethodChannel?.setMethodCallHandler(null)
        mMethodChannel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        if (!mIsWearOs) return
        mDelegate = WearDelegate(binding, mMethodChannel)
        val ref = binding.lifecycle as HiddenLifecycleReference
        ref.lifecycle.addObserver(mDelegate!!)
    }

    override fun onDetachedFromActivityForConfigChanges() = detachDelegate()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        if (!mIsWearOs) return
        mDelegate = WearDelegate(binding, mMethodChannel)
        val ref = binding.lifecycle as HiddenLifecycleReference
        ref.lifecycle.addObserver(mDelegate!!)
    }

    override fun onDetachedFromActivity() = detachDelegate()

    private fun detachDelegate() {
        mDelegate?.detach()
        mDelegate = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val delegate = mDelegate
        when (call.method) {
            "getShape" -> {
                val activity = delegate?.activity
                when {
                    activity == null -> result.error("no-activity", "No android activity available.", null)
                    activity.resources.configuration.isScreenRound -> result.success("round")
                    else -> result.success("square")
                }
            }
            "isAmbient" -> result.success(delegate?.isAmbient ?: false)
            "setAutoResumeEnabled" -> {
                val enabled = call.argument<Boolean>("enabled")
                if (delegate == null || enabled == null) {
                    result.error("not-ready", "Ambient mode controller not ready", null)
                } else {
                    delegate.setAutoResumeEnabled(enabled)
                    result.success(null)
                }
            }
            "setAmbientOffloadEnabled" -> {
                val enabled = call.argument<Boolean>("enabled")
                if (delegate == null || enabled == null) {
                    result.error("not-ready", "Ambient mode controller not ready", null)
                } else {
                    delegate.setAmbientOffloadEnabled(enabled)
                    result.success(null)
                }
            }
            else -> result.notImplemented()
        }
    }
}

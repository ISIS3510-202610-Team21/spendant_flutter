package com.example.spendant_flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.PutDataRequest
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.StandardCharsets

object WearDataLayerBridge : EventChannel.StreamHandler,
    MessageClient.OnMessageReceivedListener,
    DataClient.OnDataChangedListener {
    private const val TAG = "WearDLBridge"
    private const val METHOD_CHANNEL = "spendant_flutter/wear_data_layer"
    private const val EVENT_CHANNEL = "spendant_flutter/wear_data_layer/events"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var applicationContext: Context? = null
    private var eventSink: EventChannel.EventSink? = null
    private var listenersRegistered = false

    fun register(binaryMessenger: BinaryMessenger, context: Context) {
        applicationContext = context.applicationContext

        MethodChannel(binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }

        EventChannel(binaryMessenger, EVENT_CHANNEL).setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        updateListeners(shouldRegister = true)
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        updateListeners(shouldRegister = false)
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        Log.d(TAG, "onMessageReceived: path=${messageEvent.path} sinkActive=${eventSink != null}")
        emitEvent(
            mapOf(
                "type" to "message",
                "path" to messageEvent.path,
                "payload" to String(messageEvent.data, StandardCharsets.UTF_8),
            ),
        )
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        Log.d(TAG, "onDataChanged: ${dataEvents.count} event(s) sinkActive=${eventSink != null}")
        for (event in dataEvents) {
            if (event.type != DataEvent.TYPE_CHANGED) {
                continue
            }

            val path = event.dataItem.uri.path ?: continue
            val payload = DataMapItem.fromDataItem(event.dataItem)
                .dataMap
                .getString("payload")
                ?: continue

            Log.d(TAG, "onDataChanged: emitting path=$path")
            emitEvent(
                mapOf(
                    "type" to "data",
                    "path" to path,
                    "payload" to payload,
                ),
            )
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = applicationContext
        if (context == null) {
            result.error("no_context", "Wear data layer context is not available.", null)
            return
        }

        when (call.method) {
            "isAvailable" -> {
                val playServicesStatus =
                    GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context)
                result.success(playServicesStatus == ConnectionResult.SUCCESS)
            }

            "putDataItem" -> {
                val path = call.argument<String>("path")
                val payload = call.argument<String>("payload")
                if (path.isNullOrBlank() || payload == null) {
                    result.error("invalid_args", "path and payload are required.", null)
                    return
                }

                val request = PutDataMapRequest.create(path).apply {
                    dataMap.putString("payload", payload)
                    dataMap.putLong("updatedAt", System.currentTimeMillis())
                }.asPutDataRequest().setUrgent()

                Wearable.getDataClient(context)
                    .putDataItem(request)
                    .addOnSuccessListener { result.success(true) }
                    .addOnFailureListener { error ->
                        result.error("put_data_failed", error.message, null)
                    }
            }

            "sendMessage" -> {
                val path = call.argument<String>("path")
                val payload = call.argument<String>("payload")
                if (path.isNullOrBlank() || payload == null) {
                    result.error("invalid_args", "path and payload are required.", null)
                    return
                }

                Wearable.getNodeClient(context)
                    .connectedNodes
                    .addOnSuccessListener { nodes ->
                        Log.d(TAG, "sendMessage: path=$path connectedNodes=${nodes.size} ids=${nodes.map { it.id }}")
                        if (nodes.isEmpty()) {
                            result.success(0)
                            return@addOnSuccessListener
                        }

                        val sendTasks = nodes.map { node ->
                            Wearable.getMessageClient(context)
                                .sendMessage(
                                    node.id,
                                    path,
                                    payload.toByteArray(StandardCharsets.UTF_8),
                                )
                        }

                        Tasks.whenAllComplete(sendTasks)
                            .addOnSuccessListener { result.success(nodes.size) }
                            .addOnFailureListener { error ->
                                Log.e(TAG, "sendMessage failed: ${error.message}")
                                result.error("send_message_failed", error.message, null)
                            }
                    }
                    .addOnFailureListener { error ->
                        Log.e(TAG, "connectedNodes failed: ${error.message}")
                        result.error("connected_nodes_failed", error.message, null)
                    }
            }

            "getDataItems" -> {
                val path = call.argument<String>("path")
                Wearable.getDataClient(context)
                    .dataItems
                    .addOnSuccessListener { dataItemBuffer ->
                        val items = mutableListOf<Map<String, String>>()
                        for (item in dataItemBuffer) {
                            val itemPath = item.uri.path ?: continue
                            if (path != null && itemPath != path) continue
                            val payload = DataMapItem.fromDataItem(item)
                                .dataMap
                                .getString("payload") ?: continue
                            items.add(mapOf("path" to itemPath, "payload" to payload))
                        }
                        dataItemBuffer.release()
                        result.success(items)
                    }
                    .addOnFailureListener { error ->
                        result.error("get_data_items_failed", error.message, null)
                    }
            }

            else -> result.notImplemented()
        }
    }

    private fun updateListeners(shouldRegister: Boolean) {
        val context = applicationContext ?: return
        if (shouldRegister && !listenersRegistered) {
            Wearable.getMessageClient(context).addListener(this)
            Wearable.getDataClient(context).addListener(this)
            listenersRegistered = true
            Log.d(TAG, "programmatic listeners registered")
            return
        }

        if (!shouldRegister && listenersRegistered) {
            Wearable.getMessageClient(context).removeListener(this)
            Wearable.getDataClient(context).removeListener(this)
            listenersRegistered = false
            Log.d(TAG, "programmatic listeners removed")
        }
    }

    private fun emitEvent(payload: Map<String, String>) {
        mainHandler.post {
            eventSink?.success(payload)
        }
    }
}

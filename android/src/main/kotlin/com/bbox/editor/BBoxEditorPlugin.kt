package com.bbox.editor

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class BBoxEditorPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val executor = Executors.newSingleThreadExecutor()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "bbox_editor/native_encoder")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "encodeYuv") { result.notImplemented(); return }
        val args = call.arguments as? Map<*, *> ?: run { result.error("ARGS", "Invalid arguments", null); return }
        executor.execute {
            try {
                val output = encode(args)
                Handler(Looper.getMainLooper()).post { result.success(output) }
            } catch (e: Exception) {
                Handler(Looper.getMainLooper()).post { result.error("ENCODE", e.message, null) }
            }
        }
    }

    private fun encode(a: Map<*, *>): Map<String, Any> {
        val width = (a["width"] as Number).toInt(); val height = (a["height"] as Number).toInt()
        val y = a["y"] as ByteArray; val u = a["u"] as ByteArray; val v = a["v"] as ByteArray
        val yStride = (a["yStride"] as Number).toInt(); val uStride = (a["uStride"] as Number).toInt()
        val vStride = (a["vStride"] as Number).toInt(); val uPixel = (a["uPixel"] as Number).toInt(); val vPixel = (a["vPixel"] as Number).toInt()
        val nv21 = ByteArray(width * height + width * height / 2)
        if (a["singlePlane"] == true) {
            System.arraycopy(y, 0, nv21, 0, minOf(y.size, nv21.size))
        } else {
            for (row in 0 until height) for (col in 0 until width) nv21[row * width + col] = y[row * yStride + col]
            var p = width * height
            for (row in 0 until height / 2) for (col in 0 until width / 2) {
                nv21[p++] = v[row * vStride + col * vPixel]
                nv21[p++] = u[row * uStride + col * uPixel]
            }
        }
        val quality = ((a["quality"] as Number).toInt()).coerceIn(1, 100)
        val stream = ByteArrayOutputStream()
        YuvImage(nv21, android.graphics.ImageFormat.NV21, width, height, null).compressToJpeg(Rect(0, 0, width, height), quality, stream)
        var bitmap = BitmapFactory.decodeByteArray(stream.toByteArray(), 0, stream.size()) ?: error("JPEG decode failed")
        val rotation = ((a["rotation"] as Number).toInt() % 360 + 360) % 360
        val targetW = (a["targetWidth"] as Number?)?.toInt() ?: 0; val targetH = (a["targetHeight"] as Number?)?.toInt() ?: 0
        if (rotation != 0 || a["mirror"] == true || (targetW > 0 && targetH > 0 && (bitmap.width != targetW || bitmap.height != targetH))) {
            val m = Matrix(); if (rotation != 0) m.postRotate(rotation.toFloat()); if (a["mirror"] == true) m.postScale(-1f, 1f)
            bitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, m, true)
            if (targetW > 0 && targetH > 0) bitmap = Bitmap.createScaledBitmap(bitmap, targetW, targetH, true)
        }
        val resultWidth = bitmap.width; val resultHeight = bitmap.height
        val out = ByteArrayOutputStream(); bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out); bitmap.recycle()
        return mapOf("bytes" to out.toByteArray(), "width" to resultWidth, "height" to resultHeight)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) { channel.setMethodCallHandler(null); executor.shutdown() }
}

package com.localai.app.local_ai_app

import android.app.ActivityManager
import android.content.Context
import android.os.Environment
import android.os.StatFs
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.localai.app/system_info"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getTotalRam" -> {
                    val ram = getTotalRam()
                    result.success(ram)
                }
                "getFreeStorage" -> {
                    val storage = getFreeStorage()
                    result.success(storage)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getTotalRam(): Long {
        val actManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        actManager.getMemoryInfo(memInfo)
        return memInfo.totalMem // returns in bytes
    }

    private fun getFreeStorage(): Long {
        val path = Environment.getDataDirectory()
        val stat = StatFs(path.path)
        val blockSize = stat.blockSizeLong
        val availableBlocks = stat.availableBlocksLong
        return availableBlocks * blockSize // returns in bytes
    }
}

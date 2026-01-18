package com.chillz.app

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val PLATFORM_CHANNEL = "com.chillz/platform"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLATFORM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAndroidTV" -> {
                        result.success(isAndroidTV())
                    }
                    "getDeviceType" -> {
                        result.success(getDeviceType())
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }
    
    private fun isAndroidTV(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
        return uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
    }
    
    private fun getDeviceType(): String {
        return when {
            isAndroidTV() -> "tv"
            isTablet() -> "tablet"
            else -> "phone"
        }
    }
    
    private fun isTablet(): Boolean {
        val screenLayout = resources.configuration.screenLayout and Configuration.SCREENLAYOUT_SIZE_MASK
        return screenLayout >= Configuration.SCREENLAYOUT_SIZE_LARGE
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Enable hardware acceleration for video
        window.setFlags(
            android.view.WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            android.view.WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
        )
        
        // Keep screen on during video playback
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
    
    override fun onPause() {
        super.onPause()
        // Notify Flutter of lifecycle change for video pause
    }
    
    override fun onResume() {
        super.onResume()
        // Notify Flutter of lifecycle change for video resume
    }
}

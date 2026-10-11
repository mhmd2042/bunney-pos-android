package com.bunney.bunney_pos_android

import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The Android host for Bunney POS.
 *
 * Everything the app cannot do from Dart lives behind one method channel:
 * keeping the till's screen awake, and later the thermal-printer transports
 * (Bluetooth, USB-OTG, network). One channel rather than several plugins keeps
 * the surface small and the error handling in one place — and the printing
 * packages are unavailable in this build environment, so this is where they
 * would have gone anyway.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.bunney/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "keepScreenOn" -> {
                            val on = call.argument<Boolean>("on") ?: true
                            keepScreenOn(on)
                            result.success(true)
                        }
                        "isScreenOn" -> result.success(isScreenOn())
                        "deviceInfo" -> result.success(deviceInfo())
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    // Never crash the till over a platform call: report it and
                    // let Dart decide whether to surface or ignore it.
                    result.error("native_error", e.message ?: "unknown", null)
                }
            }
    }

    /**
     * Hold the screen on while the app is in the foreground.
     *
     * A point-of-sale counter must not sleep mid-shift: the cashier looks away
     * for a minute and the next customer has to wake the device and re-enter a
     * PIN. FLAG_KEEP_SCREEN_ON is scoped to this window, so it is released
     * automatically when the app goes to the background or is closed — no
     * wakelock permission and no battery drain once the app is not visible.
     */
    private fun keepScreenOn(on: Boolean) {
        runOnUiThread {
            if (on) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    private fun isScreenOn(): Boolean {
        val flags = window.attributes.flags
        return (flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0
    }

    /**
     * Facts about the host that the app reports on its about screen and uses to
     * decide the layout. `isTablet` follows Android's own sw600dp rule, which is
     * the same breakpoint the Dart side uses — read from the platform rather
     * than guessed from a pixel count, because density varies per device.
     */
    private fun deviceInfo(): Map<String, Any> {
        val metrics = resources.displayMetrics
        val smallestWidthDp = resources.configuration.smallestScreenWidthDp
        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "androidRelease" to Build.VERSION.RELEASE,
            "sdkInt" to Build.VERSION.SDK_INT,
            "widthPx" to metrics.widthPixels,
            "heightPx" to metrics.heightPixels,
            "densityDpi" to metrics.densityDpi,
            "widthDp" to (metrics.widthPixels / metrics.density).toInt(),
            "heightDp" to (metrics.heightPixels / metrics.density).toInt(),
            "smallestWidthDp" to smallestWidthDp,
            "isTablet" to (smallestWidthDp >= 600),
        )
    }
}

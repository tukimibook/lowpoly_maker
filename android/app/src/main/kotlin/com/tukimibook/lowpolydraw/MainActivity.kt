package com.tukimibook.lowpolydraw

import android.os.Bundle
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // Kept so the WebView is not GC'd before AdMob obtains a JavascriptEngine.
    private var adsWebView: WebView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            adsWebView = WebView(this).apply {
                settings.javaScriptEnabled = true
            }
        } catch (_: Exception) {
            // Banner load retries independently if WebView is unavailable.
        }
    }

    override fun onDestroy() {
        // Explicitly release the WebView's internal resources rather than
        // relying solely on GC alongside the Activity.
        adsWebView?.destroy()
        adsWebView = null
        super.onDestroy()
    }
}

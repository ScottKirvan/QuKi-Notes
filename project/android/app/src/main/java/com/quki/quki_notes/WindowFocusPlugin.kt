package com.quki.quki_notes

import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.annotation.CapacitorPlugin

/**
 * The WebView never tells the page when its window loses focus to a popup
 * window of the same activity (the spelling suggestion popup), so this
 * forwards the activity's own window focus changes from MainActivity.
 */
@CapacitorPlugin(name = "WindowFocus")
class WindowFocusPlugin : Plugin() {

    fun onWindowFocusChanged(hasFocus: Boolean) {
        val data = JSObject()
        data.put("hasFocus", hasFocus)
        notifyListeners("windowFocusChanged", data)
    }
}

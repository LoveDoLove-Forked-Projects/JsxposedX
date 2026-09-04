package com.jsxposed.x.feature.jsxposed.bridge

import com.whl.quickjs.wrapper.QuickJSContext
import de.robv.android.xposed.XposedBridge
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

/**
 * Xposed 官方日志能力桥接
 */
class JxLogBridge(private val qjs: QuickJSContext) {

    @Volatile
    private var currentScriptName: String = "<unknown>"

    fun beginScriptScope(scriptKey: String) {
        currentScriptName = scriptKey.substringAfterLast('/')
    }

    fun endScriptScope() {
        currentScriptName = "<unknown>"
    }

    fun <T> withScriptScope(scriptName: String, block: () -> T): T {
        val previous = currentScriptName
        currentScriptName = scriptName
        return try {
            block()
        } finally {
            currentScriptName = previous
        }
    }

    fun log(message: String): Any? {
        emit("I", message)
        return null
    }

    fun logException(message: String): Any? {
        emit("E", message)
        return null
    }

    private fun emit(level: String, message: String) {
        val encodedScript = encode(currentScriptName)
        val encodedMessage = encode(message)
        XposedBridge.log("JXCONSOLE|v1|xposed|$encodedScript|$level|$encodedMessage")
    }

    private fun encode(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8.name()).replace("+", "%20")
}

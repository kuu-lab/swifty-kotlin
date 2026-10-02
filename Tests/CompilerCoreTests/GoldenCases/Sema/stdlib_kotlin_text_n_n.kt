@file:OptIn(kotlin.ExperimentalStdlibApi::class)

package golden.sema

import kotlin.text.HexFormat
import kotlin.text.StringBuilder

@Suppress("DEPRECATION_ERROR")
fun charsToString(chars: CharArray): String = String(chars)

@Suppress("DEPRECATION_ERROR")
fun charsSliceToString(chars: CharArray): String = String(chars, 1, 3)

fun appendAll(target: StringBuilder): StringBuilder {
    return target.append("a", null, "c")
}

fun appendSlice(target: StringBuilder): StringBuilder {
    return target.appendRange("012345", 1, 4)
}

fun hexFormat(): HexFormat = HexFormat { upperCase = true }

fun stringIfEmpty(value: String): String = value.ifEmpty { "fallback" }

fun stringIfBlank(value: String): String = value.ifBlank { "fallback" }

fun builderIfEmpty(target: StringBuilder): StringBuilder = target.ifEmpty { StringBuilder("fallback") }

fun genericIfEmpty(value: CharSequence): CharSequence = value.ifEmpty { "fallback" }

fun stringOnEach(value: String): String = value.onEach { print(it) }

fun builderOnEach(target: StringBuilder): StringBuilder = target.onEach { print(it) }

fun stringOnEachIndexed(value: String): String = value.onEachIndexed { index, char -> print(index) }

fun intToRadix(value: Int): String = value.toString(16)

fun longToRadix(value: Long): String = value.toString(16)

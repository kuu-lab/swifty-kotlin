@file:OptIn(kotlin.ExperimentalStdlibApi::class)

import kotlin.text.HexFormat

@Suppress("DEPRECATION_ERROR")
fun main() {
    // String(chars) / String(chars, offset, length)
    val chars = charArrayOf('h', 'e', 'l', 'l', 'o')
    println(String(chars))
    println(String(chars, 1, 3))

    // T.append(vararg CharSequence?) / T.appendRange
    val sb = StringBuilder("A")
    sb.append("b", null, "c")
    sb.appendRange("012345", 1, 4)
    println(sb.toString())

    // HexFormat(builderAction)
    val format = HexFormat { upperCase = true }
    println(format.upperCase)

    // ifEmpty / ifBlank on String and StringBuilder
    println("".ifEmpty { "empty" })
    println("x".ifEmpty { "empty" })
    println("  ".ifBlank { "blank" })
    println("x".ifBlank { "blank" })
    println(StringBuilder("").ifEmpty { StringBuilder("empty") }.toString())

    // onEach / onEachIndexed on String, CharSequence, StringBuilder
    "abc".onEach { print(it) }
    println()
    "abc".onEachIndexed { index, c -> print("$index$c") }
    println()
    val cs: CharSequence = "xy"
    cs.onEach { print(it) }
    println()
    StringBuilder("hi").onEach { print(it) }
    println()

    // checkRadix / intToString / longToString via toString(radix)
    println(255.toString(16))
    println(255L.toString(2))
    println(Int.MIN_VALUE.toString(16))
}

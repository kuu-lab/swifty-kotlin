// KUU-2450: Adapted from JetBrains/Kotlin's pinned KT-32462 public box test.
// Original: https://github.com/JetBrains/kotlin/blob/679366a83f99851b42f64795f10ed803ff011c73/compiler/testData/codegen/box/callableReference/function/kt32462.kt
// Revision: 679366a83f99851b42f64795f10ed803ff011c73
// Git blob: c9b96e6f1eef957bca74f079a445e3dff92e68f4
// Original SHA-256: 6399a7c3916e7074166038618dc74863f0f2fcb0b21e31bf68224c4edf0e52c4
// SPDX-License-Identifier: Apache-2.0
// KOTLINC_FLAGS: -Xjdk-release=17
fun decodeValue(value: String): Any {
    return when (value[0]) {
        'F' -> String::toFloat
        'B' -> String::toBoolean
        'I' -> String::toInt
        else -> throw IllegalArgumentException("Unexpected value prefix: ${value[0]}")
    }(value.substring(2))
}

fun box(): String = "OK"

fun parseIntValue(value: String): Int = 42
fun parseBooleanValue(value: String): Boolean = value == "42"
fun parseOtherIntValue(value: String): Int = if (value == "42") 42 else 0

fun minimalReproducer(): String = when (true) {
    true -> ::parseIntValue
    false -> ::parseBooleanValue
}("42").toString()

fun explicitExpectedTypeControl(): String {
    val parser: (String) -> Any = when (true) {
        true -> ::parseIntValue
        false -> ::parseBooleanValue
    }
    return parser("42").toString()
}

fun sameReturnTypeControl(): String = when (true) {
    true -> ::parseIntValue
    false -> ::parseOtherIntValue
}("42").toString()

fun main() {
    println(decodeValue("I42"))
    println(box())
    println(minimalReproducer())
    println(explicitExpectedTypeControl())
    println(sameReturnTypeControl())
}

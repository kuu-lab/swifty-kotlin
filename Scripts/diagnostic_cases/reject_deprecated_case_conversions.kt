// EXPECT-REJECT
// DEPRECATION only suppresses warning-level deprecations in kotlinc; these
// case-conversion members are error-level since Kotlin 2.1, so the calls must
// still be rejected.
@file:Suppress("DEPRECATION")

fun main() {
    println('a'.toUpperCase())
    println('A'.toLowerCase())
    println('a'.toTitleCase())
    println("abc".toLowerCase())
    println("abc".toUpperCase())
}

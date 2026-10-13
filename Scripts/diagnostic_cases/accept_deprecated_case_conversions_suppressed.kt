// EXPECT-ACCEPT
// DEPRECATION_ERROR is the kotlinc suppression name for error-level
// deprecations; it must silence the deprecated case-conversion calls.
@file:Suppress("DEPRECATION_ERROR")

fun main() {
    println('a'.toUpperCase())
    println('A'.toLowerCase())
    println('a'.toTitleCase())
    println("abc".toLowerCase())
    println("abc".toUpperCase())
}

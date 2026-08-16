@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

fun main() {
    try {
        throw KotlinNothingValueException("expected")
    } catch (e: KotlinNothingValueException) {
        println(e.message)
    }
}

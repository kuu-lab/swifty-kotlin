import kotlinx.io.EOFException

fun main() {
    val message: kotlin.String = "state"
    try {
        throw kotlin.IllegalStateException(message)
    } catch (e: kotlin.IllegalArgumentException) {
        println("wrong sibling")
    } catch (e: kotlin.IllegalStateException) {
        println("qualified: ${e.message}")
    }

    try {
        throw kotlin.UninitializedPropertyAccessException("uninitialized")
    } catch (e: kotlin.UninitializedPropertyAccessException) {
        println("property: ${e.message}")
    }

    try {
        throw kotlin.IllegalStateException("parent")
    } catch (e: kotlin.RuntimeException) {
        println("parent: ${e.message}")
    }

    try {
        throw kotlin.Exception("throwable")
    } catch (e: kotlin.Throwable) {
        println("throwable: ${e.message}")
    }

    try {
        throw java.io.IOException("java")
    } catch (e: kotlin.IllegalStateException) {
        println("wrong java handler")
    } catch (e: java.io.IOException) {
        println("java: ${e.message}")
    }

    try {
        throw kotlinx.io.EOFException("kotlinx")
    } catch (e: kotlin.IllegalArgumentException) {
        println("wrong kotlinx handler")
    } catch (e: kotlinx.io.EOFException) {
        println("kotlinx: ${e.message}")
    }

    try {
        throw kotlin.IllegalStateException("short")
    } catch (e: IllegalStateException) {
        println("unqualified: ${e.message}")
    }
}

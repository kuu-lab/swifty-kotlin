@file:OptIn(kotlin.js.ExperimentalJsStatic::class)

// Kotlin/JS 2.3.10 accepts this top-level annotation; it has no extra class static member to emit.
@kotlin.js.JsStatic
fun topLevel(): String = "top-level"

class Ordinary {
    companion object {
        @kotlin.js.JsStatic
        fun message(): String = "companion"
    }
}

interface Contract {
    companion object {
        @kotlin.js.JsStatic
        fun message(): String = "interface"
    }
}

fun main() {
    println(topLevel())
    println(Ordinary.message())
    println(Contract.message())
}

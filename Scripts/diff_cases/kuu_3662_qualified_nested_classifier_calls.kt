interface Contract {
    fun interface Entry { fun get(): String }
    interface Greeter {
        companion object { operator fun invoke(text: String): String = "invoke:" + text }
    }
    class Nested { fun get(): String = "nested" }
    object Obj { operator fun invoke(text: String): String = "obj:" + text }
    object Zero { operator fun invoke(): String = "zero" }
    class Factory {
        fun get(): String = "factory"
        companion object { operator fun invoke(text: String): String = "f:" + text }
    }
}

fun sam(): Contract.Entry = Contract.Entry { "sam" }
fun invoke(): String = Contract.Greeter("inner")

fun main() {
    println(sam().get())
    println(invoke())
    println(Contract.Nested().get())
    println(Contract.Obj("inner"))
    println(Contract.Zero())
    println(Contract.Factory("inner"))
}

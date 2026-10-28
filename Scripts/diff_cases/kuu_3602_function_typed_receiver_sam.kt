// KUU-3602: the SAM method has a function-typed extension receiver.
fun interface S {
    fun (Int.() -> String).accept(): String
}

fun box(): String {
    val receiver: Int.() -> String = { if (this == 42) "OK" else "wrong receiver" }
    val sam = S { this(42) }
    return with(sam) { receiver.accept() }
}

fun main() {
    println(box())
}

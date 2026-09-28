package golden.sema

// BUG-C: an extension function whose receiver is itself a function type.
infix fun <A, B, C> ((A) -> B).then(g: (B) -> C): (A) -> C = { g(this(it)) }
fun ((Int) -> Int).applyTwice(x: Int): Int = this(this(x))

fun functionTypeReceiverExtension(): Int {
    val double: (Int) -> Int = { it * 2 }
    val increment: (Int) -> Int = { it + 1 }
    val combined = double then increment
    return combined(3) + double.applyTwice(1)
}

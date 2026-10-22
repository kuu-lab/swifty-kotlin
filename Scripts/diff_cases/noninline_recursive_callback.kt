// DIFF_JVM
// KUU-2148: ordinary recursive callbacks need emitted native bodies.
fun process(value: Int, handler: (Int) -> Int): Int {
    return if (value == 0) handler(value) else process(value - 1, handler)
}

fun Int.processExtension(handler: (Int) -> Int): Int {
    return if (this == 0) handler(this) else (this - 1).processExtension(handler)
}

fun even(value: Int, handler: (Int) -> Int): Int {
    return if (value == 0) handler(value) else odd(value - 1, handler)
}

fun odd(value: Int, handler: (Int) -> Int): Int {
    return if (value == 0) handler(value + 1) else even(value - 1, handler)
}

fun defaultProcess(value: Int, handler: (Int) -> Int = { it + 3 }): Int {
    return if (value == 0) handler(value) else defaultProcess(value - 1, handler)
}

fun wrappedProcess(value: Int, handler: (Int) -> Int): Int {
    return if (value == 0) handler(value) else inlineStep(value - 1, handler)
}
inline fun inlineStep(value: Int, noinline handler: (Int) -> Int): Int = wrappedProcess(value, handler)

fun plain(value: Int, handler: (Int) -> Int): Int = handler(value)
inline fun explicitInline(value: Int, handler: (Int) -> Int): Int = handler(value)

fun main() {
    println(process(5) { it + 7 })
    val offset = 11
    val captured: (Int) -> Int = { it + offset }
    println(process(value = 4, handler = captured))
    println(3.processExtension(captured))
    println(even(4, captured))
    println(even(3, captured))
    println(defaultProcess(4))
    println(wrappedProcess(4, captured))
    val reference = ::process
    println(reference(3, captured))
    println(plain(2, captured))
    println(explicitInline(3, captured))
    try {
        process(3) { throw IllegalArgumentException("callback") }
    } catch (e: IllegalArgumentException) {
        println("caught")
    }
}

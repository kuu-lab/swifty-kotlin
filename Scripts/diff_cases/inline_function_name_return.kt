inline fun invokeBlock(block: () -> Unit) {
    println("before")
    block()
    println("after")
}

inline fun String.tryIt(block: () -> Unit) { block() }
inline fun predicate(block: () -> Boolean): Boolean = block()

fun unitReturn() {
    invokeBlock { return@unitReturn }
    println("unreachable-unit")
}

fun valueReturn(): String {
    predicate { return@valueReturn "value" }
    return "unreachable-value"
}

fun extensionReturn(s: String): String {
    s.tryIt { return@extensionReturn "extension" }
    return "unreachable-extension"
}

fun nestedReturn(): Int {
    invokeBlock { invokeBlock { return@nestedReturn 23 } }
    return -1
}

fun localReturn(): Int {
    invokeBlock { return@invokeBlock }
    return 42
}

fun shadowReturn(): String {
    predicate shadowReturn@ { return@shadowReturn true }
    return "shadow"
}

fun finallyReturn(): Int {
    invokeBlock {
        try {
            return@finallyReturn 31
        } finally {
            println("inner-finally")
        }
    }
    return -1
}

fun capturedFinallyReturn(value: Int): Int {
    invokeBlock {
        try {
            return@capturedFinallyReturn value
        } finally {
            println(value + 1)
        }
    }
    return -1
}

fun localFunctionReturn(): Int {
    fun local(): Int {
        invokeBlock { return@local 19 }
        return -1
    }
    return local()
}

fun directReturn(): Int {
    run { return@directReturn 5 }
    return -1
}

fun main() {
    unitReturn()
    println(valueReturn())
    println(extensionReturn("x"))
    println(nestedReturn())
    println(localReturn())
    println(shadowReturn())
    println(finallyReturn())
    println(capturedFinallyReturn(37))
    println(localFunctionReturn())
    println(directReturn())
}

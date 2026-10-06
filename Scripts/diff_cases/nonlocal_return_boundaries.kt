// KUU-1225: legal lambda-local returns and inline non-local returns remain valid.
fun applyTwice(action: (Int) -> Int): Int = action(action(1))
inline fun applyTwiceInline(action: (Int) -> Int): Int = action(action(1))
inline fun invokeBlock(block: () -> Unit) { block() }

fun inlineConditionalReturn() {
    applyTwiceInline { if (it == 1) return else it * 2 }
    println("unreachable")
}

fun inlineResult(): Int {
    invokeBlock { invokeBlock { return 7 } }
    return -1
}

fun queryReturn(source: String, mode: Int): String {
    when (mode) {
        0 -> source.first { return "first" }
        1 -> source.firstOrNull { return "firstOrNull" }
        2 -> source.last { return "last" }
        3 -> source.lastOrNull { return "lastOrNull" }
        4 -> source.single { return "single" }
        5 -> source.singleOrNull { return "singleOrNull" }
    }
    return "fallback"
}

fun trimReturn(source: String, mode: Int): String {
    when (mode) {
        0 -> source.trim { return "trim" }
        1 -> source.trimStart { return "trimStart" }
        2 -> source.trimEnd { return "trimEnd" }
    }
    return "fallback"
}

fun main() {
    println(applyTwice { if (it == 1) return@applyTwice 3 else it * 2 })
    println(applyTwice(fun(value: Int): Int { if (value == 1) return 3; return value * 2 }))
    println(inlineResult())
    inlineConditionalReturn()
    println("conditional return")
    for (mode in 0..5) println(queryReturn("abc", mode))
    for (mode in 0..2) println(trimReturn(" abc ", mode))
}

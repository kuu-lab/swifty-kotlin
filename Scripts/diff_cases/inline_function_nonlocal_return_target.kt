inline fun aroundTarget(block: () -> Unit) { block() }

inline fun inlineValue(): Int {
    aroundTarget { return 42 }
    return -1
}

inline fun capturedValue(seed: Int): Int {
    var value = seed
    aroundTarget { aroundTarget { value += 1; return value } }
    return -1
}

inline fun inlineUnit() {
    aroundTarget { return }
    println("unreachable-unit")
}

inline fun inlineString(): String {
    try { aroundTarget { return "result" } } finally { println("string-finally") }
    return "wrong"
}

inline fun overridingValue(): Int {
    try { aroundTarget { return 50 } } finally { aroundTarget { return 51 } }
    return -1
}

inline fun guardedTarget(block: () -> Unit) {
    try { block() } finally { println("guard-finally") }
}

inline fun finallyValue(): Int {
    try {
        guardedTarget { return 43 }
    } finally { println("value-finally") }
    return -1
}

inline fun mixedTarget(exit: Boolean, block: () -> Unit): Int {
    try {
        aroundTarget { if (exit) return 44 }
        block()
    } finally { println("mixed-finally") }
    return 45
}

fun outerTarget(exit: Boolean): Int {
    try {
        println(mixedTarget(exit) { return 46 })
        println("outer-continued")
    } finally { println("outer-finally") }
    return 47
}

inline fun mixedString(exit: Boolean, block: () -> Unit): String {
    try {
        aroundTarget { if (exit) return "own-string" }
        block()
    } finally { println("mixed-string-finally") }
    return "normal-string"
}

fun outerString(exit: Boolean): Int {
    try {
        println(mixedString(exit) { return 66 })
    } finally { println("outer-string-finally") }
    return 67
}

fun main() {
    println("before")
    println(inlineValue())
    println(inlineValue())
    println(capturedValue(49))
    inlineUnit()
    println("after-unit")
    println(inlineString())
    println(overridingValue())
    try {
        println(finallyValue())
        println("after-value")
    } finally { println("main-finally") }
    println(outerTarget(true))
    println(outerTarget(false))
    println(outerString(true))
    println(outerString(false))
    println("after")
}

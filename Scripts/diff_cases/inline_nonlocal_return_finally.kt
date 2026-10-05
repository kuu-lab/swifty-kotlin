inline fun once(block: () -> Unit) { block() }
inline fun guarded(block: () -> Unit) {
    try { block() } finally { println("inline-finally") }
}

fun bare(): Int {
    try { once { return 31 } } finally { println("outer-finally") }
    return -1
}

fun nested(): Int {
    try {
        try {
            guarded {
                try { return 32 } finally { println("lambda-finally") }
            }
        } finally { println("inner-finally") }
    } finally { println("outer-finally") }
    return -1
}

fun snapshot(): Int {
    var value = 33
    try { once { value += 1; return value } }
    finally { value += 10; println(value) }
    return -1
}

fun overridden(): Int {
    try { once { return 35 } } finally { return 36 }
    return -1
}

fun localReturn(): Int {
    try { once { return@once }; println("continued") }
    finally { println("local-finally") }
    return 37
}

fun conditional(exit: Boolean): Int {
    try { once { if (exit) return 38 }; println("normal") }
    finally { println("conditional-finally") }
    return 39
}

fun fromCatch(): Int {
    try { throw IllegalStateException("original") }
    catch (e: IllegalStateException) { once { return 40 } }
    finally { println("catch-finally") }
    return -1
}

fun throwingFinally(): Int {
    try {
        try { once { return 41 } }
        catch (e: IllegalStateException) { println("wrong-catch") }
        finally { throw IllegalStateException("cleanup") }
    } catch (e: IllegalStateException) { println(e.message) }
    finally { println("throw-outer-finally") }
    return 42
}

fun unitReturn() {
    try { once { return } } finally { println("unit-finally") }
    println("unreachable")
}

fun stringReturn(): String {
    try { guarded { return "result" } } finally { println("string-finally") }
    return "wrong"
}

fun doubleReturn(): Double {
    try { guarded { return 1.25 } } finally { println("double-finally") }
    return 0.0
}

fun eagerCleanup(): Int {
    try {
        try { return 1 }
        finally { println("eager-inner"); once { return 43 } }
    } finally { println("eager-outer") }
    return -1
}

fun nullableReturn(value: Int?): Int? {
    try { once { return value } } finally { println("nullable-finally") }
    return -1
}

fun anyReturn(): Any {
    try { once { return 1.25 } } finally { println("any-finally") }
    return 0
}

fun nullableDoubleReturn(value: Double?): Double? {
    try { once { return value } } finally { println("nullable-double-finally") }
    return -1.0
}

fun main() {
    println(bare())
    println(nested())
    println(snapshot())
    println(overridden())
    println(localReturn())
    println(conditional(true))
    println(conditional(false))
    println(fromCatch())
    println(throwingFinally())
    unitReturn()
    println(stringReturn())
    println(doubleReturn())
    println(eagerCleanup())
    println(nullableReturn(null))
    println(nullableReturn(0))
    println(nullableReturn(44))
    println(anyReturn())
    println(nullableDoubleReturn(null))
    println(nullableDoubleReturn(1.25))
}

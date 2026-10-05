private const val LF: Byte = 10

fun byteSubjectWhen(b: Byte): Int {
    when (b) { LF -> return 1 }
    return 0
}

fun encodeToImpl(fromIndex: Int, toIndex: Int): Int {
    var start = fromIndex
    if (start >= toIndex) return 0
    while (true) {
        start += 1
        when { start >= toIndex -> break }
    }
    return start
}

fun loopStatements(): Int {
    var sum = 0
    for (n in 1..4) {
        sum += n
        when (n) { 2 -> continue; 3 -> break }
    }
    var n = 0
    do {
        n += 1
        when { n >= 3 -> break }
    } while (n < 10)
    var k = 0
    while (k < 4) {
        k += 1
        when { k == 2 -> continue; k == 3 -> break }
    }
    return sum + n + k
}

fun runAction(action: () -> Unit) { action() }

fun nestedStatements(flag: Boolean, n: Int): Int {
    var result = 0
    if (flag) {
        when (n) { 1 -> result += 1 }
    } else {
        when { n > 0 -> result += 2 }
    }
    when (n) {
        1 -> { when { flag -> result += 4 } }
        else -> { when (n) { 2 -> result += 8 } }
    }
    when {
        flag -> { when (n) { 1 -> result += 16 } }
        else -> { when { n > 0 -> result += 32 } }
    }
    try {
        if (n == 2) throw IllegalStateException("two")
        when { flag -> result += 64 }
    } catch (e: IllegalStateException) {
        when (n) { 2 -> result += 128 }
    } finally {
        when { flag -> result += 256 }
    }
    runAction { when { flag -> result += 512 } }
    val action: () -> Unit = { when (n) { 1 -> result += 1024 } }
    action()
    return result
}

fun expressionWithFinally(flag: Boolean): Int = try {
    7
} finally {
    when { flag -> println("finally") }
}

fun main() {
    println(byteSubjectWhen(10))
    println(byteSubjectWhen(5))
    println(encodeToImpl(0, 3))
    println(encodeToImpl(3, 3))
    println(loopStatements())
    println(nestedStatements(true, 1))
    println(nestedStatements(false, 1))
    println(nestedStatements(true, 2))
    println(nestedStatements(false, 2))
    println(nestedStatements(false, 0))
    println(expressionWithFinally(true))
    println(expressionWithFinally(false))
}

fun escape(): Int {
    try { println("try") } finally { return 36 }
}

fun caught(): Int {
    try { throw IllegalStateException("caught") }
    catch (e: IllegalStateException) { println(e.message) }
    finally { return 37 }
}

fun nested(): Int {
    try { println("outer") }
    finally { try { println("inner") } finally { return 38 } }
}

fun branches(flag: Boolean): Int {
    if (flag) {
        try { println("left") } finally { return 39 }
    } else {
        try { println("right") } finally { return 40 }
    }
}

fun exhaustive(flag: Boolean): Int {
    when (flag) {
        true -> try { println("true") } finally { return 41 }
        false -> try { println("false") } finally { return 42 }
    }
}

fun conditional(flag: Boolean): Int {
    try { println("conditional") }
    finally { if (flag) return 43 else return 44 }
}

fun throwing(): Int {
    try { println("throwing") } finally { throw IllegalStateException("cleanup") }
}

fun value(): String {
    val ignored: Int = try { 1 } catch (e: Exception) { 2 } finally { return "escape" }
}

fun argument(): Int {
    println(try { 1 } finally { return 45 })
}

fun partial(flag: Boolean): Int {
    try { println("partial") } finally { if (flag) return 46 }
    return 47
}

fun nestedCatch(): Int {
    try {
        try { println("inner-try") } finally { return 48 }
    } catch (e: Exception) { return 49 }
}

fun main() {
    println(escape())
    println(caught())
    println(nested())
    println(branches(true))
    println(branches(false))
    println(exhaustive(true))
    println(exhaustive(false))
    println(conditional(true))
    println(conditional(false))
    try { println(throwing()) } catch (e: IllegalStateException) { println(e.message) }
    println(value())
    println(argument())
    println(partial(true))
    println(partial(false))
    println(nestedCatch())
}

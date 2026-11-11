package klibexceptions

fun guarded(mode: Int): Int = try {
    require(mode > 0)
    if (mode == 2 || mode == 4) throw NumberFormatException("number")
    if (mode == 3 || mode == 5) throw UnsupportedOperationException("unmatched")
    10
} catch (error: NumberFormatException) {
    println(error.message)
    if (mode == 4) throw error
    20
} catch (error: IllegalArgumentException) {
    println(error.message)
    30
} finally {
    println("finally")
    if (mode == 5) check(false)
}

fun nested(): Int = try {
    try {
        guarded(3)
    } finally {
        println("outer finally")
    }
} catch (error: UnsupportedOperationException) {
    println(error.message)
    40
}

fun earlyReturn(exit: Boolean): Int {
    var value = 50
    try {
        if (exit) return value
    } finally {
        var cleanup = 0
        cleanup += 1
        println(cleanup)
        value = 0
    }
    return value
}

fun loopExits(): Int {
    var i = 0
    while (i < 2) {
        i += 1
        try {
            if (i == 1) continue
            break
        } finally {
            println(i)
        }
    }
    return i
}

// Error cases for return type mismatches (KSWIFTK-TYPE-* / KSWIFTK-SEMA-*)

// ERROR: Function declares Int but returns String
fun wrongReturn(): Int {
    return "not an int"  // KSWIFTK-TYPE-0001: type constraint could not be satisfied (expected Int, found String)
}

// ERROR: Function declares String but returns nothing (missing return)
fun missingReturn(): String {
    val x = 1
    // Missing return — KSWIFTK-TYPE-0001: type constraint could not be satisfied, reported on the fun line (a 'return' is required in a block body)
}

// ERROR: Multiple return paths with mismatched types
fun mismatchedPaths(flag: Boolean): Int {
    return if (flag) {
        "true branch"  // KSWIFTK-TYPE-0001: type constraint could not be satisfied, reported on the `return if` line
    } else {
        0
    }
}

// ERROR: Lambda return type mismatch
val transform: (Int) -> Int = { x ->
    "result"  // KSWIFTK-TYPE-0001: type constraint could not be satisfied (expected Int, found String)
}

// ERROR: Suspend function returning non-deferred value as Deferred
suspend fun badSuspendReturn(): Int {
    return "wrong"  // KSWIFTK-TYPE-0001: type constraint could not be satisfied (expected Int, found String)
}

fun main() {}

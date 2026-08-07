// Error cases for return type mismatches (KSWIFTK-TYPE-* / KSWIFTK-SEMA-*)

// ERROR: Function declares Int but returns String
fun wrongReturn(): Int {
    return "not an int"  // KSWIFTK-TYPE-0030: type mismatch, expected Int found String
}

// ERROR: Function declares String but returns nothing (missing return)
fun missingReturn(): String {
    val x = 1
    // Missing return — KSWIFTK-SEMA-0060: a 'return' expression required in a function with a block body
}

// ERROR: Multiple return paths with mismatched types
fun mismatchedPaths(flag: Boolean): Int {
    return if (flag) {
        "true branch"  // KSWIFTK-TYPE-0031: type mismatch, expected Int found String
    } else {
        0
    }
}

// ERROR: Lambda return type mismatch
val transform: (Int) -> Int = { x ->
    "result"  // KSWIFTK-TYPE-0032: type mismatch, expected Int found String
}

// ERROR: Suspend function returning non-deferred value as Deferred
suspend fun badSuspendReturn(): Int {
    return "wrong"  // KSWIFTK-TYPE-0033: type mismatch, expected Int found String
}

fun main() {}

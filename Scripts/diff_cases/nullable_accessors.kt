fun main() {
    val list = listOf(1, 2, 3)
    val empty = emptyList<Int>()

    // STDLIB-543: firstOrNull (no predicate)
    println("firstOrNull(list)=${list.firstOrNull()}")
    println("firstOrNull(empty)=${empty.firstOrNull()}")

    // STDLIB-543: firstOrNull (predicate - match)
    println("firstOrNull{>1}=${list.firstOrNull { it > 1 }}")
    // STDLIB-543: firstOrNull (predicate - no match)
    println("firstOrNull{>10}=${list.firstOrNull { it > 10 }}")
    // STDLIB-543: firstOrNull (predicate - empty list)
    println("firstOrNull{empty}=${empty.firstOrNull { it > 0 }}")

    // STDLIB-544: lastOrNull (no predicate)
    println("lastOrNull(list)=${list.lastOrNull()}")
    println("lastOrNull(empty)=${empty.lastOrNull()}")

    // STDLIB-544: lastOrNull (predicate - match)
    println("lastOrNull{<3}=${list.lastOrNull { it < 3 }}")
    // STDLIB-544: lastOrNull (predicate - no match)
    println("lastOrNull{>10}=${list.lastOrNull { it > 10 }}")
    // STDLIB-544: lastOrNull (predicate - empty list)
    println("lastOrNull{empty}=${empty.lastOrNull { it > 0 }}")

    // STDLIB-545: singleOrNull (no predicate - single element)
    println("singleOrNull(single)=${listOf(42).singleOrNull()}")
    // STDLIB-545: singleOrNull (no predicate - empty list)
    println("singleOrNull(empty)=${empty.singleOrNull()}")
    // STDLIB-545: singleOrNull (no predicate - multi-element -> null)
    println("singleOrNull(multi)=${list.singleOrNull()}")

    // STDLIB-545: singleOrNull (predicate - unique match)
    println("singleOrNull{==2}=${list.singleOrNull { it == 2 }}")
    // STDLIB-545: singleOrNull (predicate - no match)
    println("singleOrNull{>10}=${list.singleOrNull { it > 10 }}")
    // STDLIB-545: singleOrNull (predicate - multiple matches -> null)
    println("singleOrNull{>1}=${list.singleOrNull { it > 1 }}")
    // STDLIB-545: singleOrNull (predicate - empty list)
    println("singleOrNull{empty}=${empty.singleOrNull { it > 0 }}")

    // getOrNull (index-based nullable access)
    println("getOrNull(0)=${list.getOrNull(0)}")
    println("getOrNull(5)=${list.getOrNull(5)}")
    println("getOrNull(empty)=${empty.getOrNull(0)}")
}

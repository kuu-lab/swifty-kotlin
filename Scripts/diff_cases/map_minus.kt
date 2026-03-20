fun main() {
    // 1. Basic: Map.minus(key) — single key removal
    val base = mapOf("a" to 1, "b" to 2, "c" to 3, "d" to 4)
    val r1 = base - "b"
    println(r1)           // {a=1, c=3, d=4}

    // 2. Removing a key that does not exist
    val r2 = base - "z"
    println(r2)           // {a=1, b=2, c=3, d=4}
    println(r2 == base)   // true

    // 3. Map.minus(Iterable) — remove multiple keys via list
    val r3 = base - listOf("a", "c")
    println(r3)           // {b=2, d=4}

    // 4. Map.minus(Iterable) — empty list
    val r4 = base - listOf<String>()
    println(r4)           // {a=1, b=2, c=3, d=4}
    println(r4 == base)   // true

    // 5. Map.minus(Iterable) — all keys removed
    val r5 = base - listOf("a", "b", "c", "d")
    println(r5)           // {}
    println(r5.isEmpty())  // true

    // 6. Map.minus(Iterable) — some keys exist, some don't
    val r6 = base - listOf("a", "z", "c", "w")
    println(r6)           // {b=2, d=4}

    // 7. Map.minus(Sequence) — remove via sequence
    val r7 = base - sequenceOf("b", "d")
    println(r7)           // {a=1, c=3}

    // 8. Map.minus(Array) — remove via array
    val keys = arrayOf("a", "d")
    val r8 = base - keys
    println(r8)           // {b=2, c=3}

    // 9. Original map is unchanged (immutability)
    println(base)          // {a=1, b=2, c=3, d=4}

    // 10. Chained minus
    val r9 = base - "a" - "d"
    println(r9)           // {b=2, c=3}

    // 11. Empty map minus
    val empty = emptyMap<String, Int>()
    val r10 = empty - "a"
    println(r10)          // {}
    println(r10.isEmpty()) // true

    // 12. Map with Int keys
    val intMap = mapOf(1 to "one", 2 to "two", 3 to "three")
    val r11 = intMap - 2
    println(r11)          // {1=one, 3=three}

    // 13. Minus with set of keys
    val r12 = base - setOf("a", "b")
    println(r12)          // {c=3, d=4}

    // 14. minusAssign on MutableMap
    val mutable = mutableMapOf("x" to 10, "y" to 20, "z" to 30)
    mutable -= "y"
    println(mutable)      // {x=10, z=30}

    // 15. minusAssign with list of keys
    mutable -= listOf("x", "z")
    println(mutable)      // {}

    // 16. Size after minus
    val r13 = base - "a"
    println(r13.size)     // 3

    // 17. containsKey after minus
    val r14 = base - "b"
    println(r14.containsKey("b"))  // false
    println(r14.containsKey("a"))  // true

    // 18. Minus with duplicate keys in list
    val r15 = base - listOf("a", "a", "b", "b")
    println(r15)          // {c=3, d=4}

    // 19. Values/keys after minus
    val r16 = base - "a" - "d"
    println(r16.keys.toList().sorted())    // [b, c]
    println(r16.values.toList().sorted())  // [2, 3]

    // 20. Map with nullable values
    val nullMap = mapOf("a" to null, "b" to 1, "c" to null)
    val r17 = nullMap - "a"
    println(r17)          // {b=1, c=null}
}

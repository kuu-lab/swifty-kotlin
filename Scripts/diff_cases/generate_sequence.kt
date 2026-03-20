fun main() {
    // 1. Basic seed + next function
    val powers = generateSequence(1) { it * 2 }.take(6).toList()
    println(powers)

    // 2. Null termination from next function
    val limited = generateSequence(1) { if (it < 10) it + 3 else null }.toList()
    println(limited)

    // 3. Seed function overload (seedFunction returns nullable)
    val fromSeed = generateSequence({ 42 }) { if (it < 100) it * 2 else null }.toList()
    println(fromSeed)

    // 4. Seed function returning null immediately => empty sequence
    val empty = generateSequence<Int>({ null }) { it + 1 }.toList()
    println(empty)

    // 5. take(0) => empty
    val takeZero = generateSequence(1) { it + 1 }.take(0).toList()
    println(takeZero)

    // 6. take(1) => only seed
    val takeOne = generateSequence(100) { it + 1 }.take(1).toList()
    println(takeOne)

    // 7. first() on generated sequence
    val first = generateSequence(5) { it + 1 }.first()
    println(first)

    // 8. drop + take
    val dropTake = generateSequence(0) { it + 1 }.drop(5).take(3).toList()
    println(dropTake)

    // 9. filter + take
    val evens = generateSequence(1) { it + 1 }.filter { it % 2 == 0 }.take(5).toList()
    println(evens)

    // 10. map + take
    val mapped = generateSequence(1) { it + 1 }.map { it * it }.take(5).toList()
    println(mapped)

    // 11. count with take
    val cnt = generateSequence(1) { it + 1 }.take(10).count()
    println(cnt)

    // 12. toSet with take
    val asSet = generateSequence(1) { if (it < 4) it + 1 else null }.toSet()
    println(asSet)

    // 13. sum via sumOf
    val total = generateSequence(1) { if (it < 5) it + 1 else null }.sumOf { it }
    println(total)

    // 14. joinToString
    val joined = generateSequence(1) { if (it < 5) it + 1 else null }.joinToString(", ")
    println(joined)

    // 15. any / none / all with take
    val hasEven = generateSequence(1) { it + 1 }.take(5).any { it % 2 == 0 }
    println(hasEven)

    val allPositive = generateSequence(1) { it + 1 }.take(5).all { it > 0 }
    println(allPositive)

    val noneNegative = generateSequence(1) { it + 1 }.take(5).none { it < 0 }
    println(noneNegative)

    // 16. String sequence
    val strings = generateSequence("a") { if (it.length < 4) it + "a" else null }.toList()
    println(strings)

    // 17. zip two generated sequences
    val zipped = generateSequence(1) { it + 1 }.zip(generateSequence(10) { it + 10 }).take(4).toList()
    println(zipped)

    // 18. flatMap + take
    val flat = generateSequence(1) { it + 1 }.flatMap { sequenceOf(it, it * 10) }.take(6).toList()
    println(flat)

    // 19. forEach with take
    val sb = StringBuilder()
    generateSequence(1) { it + 1 }.take(4).forEach { sb.append(it) }
    println(sb.toString())

    // 20. Chained: generate + filter + map + take
    val chained = generateSequence(1) { it + 1 }
        .filter { it % 3 == 0 }
        .map { it * 2 }
        .take(4)
        .toList()
    println(chained)
}

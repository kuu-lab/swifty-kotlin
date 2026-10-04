package golden.sema

fun <A, B, C> copyTriple(value: Triple<A, B, C>): Triple<A, B, C> = value.copy()

fun exerciseTripleMembers(): Triple<Int, String, Boolean> {
    val triple = Triple(1, "one", true)
    val copied = triple.copy()
    val firstChanged = triple.copy(first = 2)
    val secondChanged = triple.copy(second = "two")
    val thirdChanged = triple.copy(third = false)
    val partialChanged = triple.copy(first = 3, third = false)
    val allChanged = triple.copy(4, "four", false)
    val genericCopied = copyTriple(triple)
    val nullable: Triple<Int?, String?, Boolean?> = Triple(null, "nullable", null)
    val nullableChanged = nullable.copy(first = 42, third = true)

    println(triple.first)
    println(triple.second)
    println(triple.third)
    println(triple.component1())
    println(triple.component2())
    println(triple.component3())
    println(copied)
    println(firstChanged)
    println(secondChanged)
    println(thirdChanged)
    println(partialChanged)
    println(allChanged)
    println(genericCopied)
    println(nullable)
    println(nullableChanged)
    return copied
}

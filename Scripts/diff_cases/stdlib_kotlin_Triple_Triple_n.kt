// Diff regression for kotlin.Triple receiver members.
fun <A, B, C> copyTriple(value: Triple<A, B, C>): Triple<A, B, C> = value.copy()

fun main() {
    val triple = Triple(1, "one", true)
    val copied = triple.copy()
    val firstChanged = triple.copy(first = 2)
    val secondChanged = triple.copy(second = "two")
    val thirdChanged = triple.copy(third = false)
    val partialChanged = triple.copy(first = 3, third = false)
    val allChanged = triple.copy(4, "four", false)

    println(triple)
    println(copied)
    println(firstChanged)
    println(secondChanged)
    println(thirdChanged)
    println(partialChanged)
    println(allChanged)
    println("${triple.first} ${triple.second} ${triple.third}")
    println("${triple.component1()} ${triple.component2()} ${triple.component3()}")

    val genericCopied = copyTriple(triple)
    println(genericCopied)

    val nullable: Triple<Int?, String?, Boolean?> = Triple(null, "nullable", null)
    val nullableChanged = nullable.copy(first = 42, third = true)
    println(nullable)
    println(nullableChanged)
    println("${nullableChanged.first} ${nullableChanged.second} ${nullableChanged.third}")
    println("${nullableChanged.component1()} ${nullableChanged.component2()} ${nullableChanged.component3()}")
}

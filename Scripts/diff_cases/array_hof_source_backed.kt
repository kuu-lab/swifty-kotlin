// KSP-433: Array<T> HOFs are backed by bundled Kotlin source instead of the
// kk_array_* runtime bridges. Covers the transform/filter/aggregate/search
// families plus joinToString / asSequence, including element types whose
// erased representation is boxed (Double, Char, String).
fun main() {
    val nums = arrayOf(1, 2, 3, 4, 5)

    println(nums.map { it * 2 })
    println(nums.mapIndexed { index, value -> index * value })
    println(nums.mapNotNull { if (it % 2 == 1) it else null })
    println(nums.flatMap { listOf(it, it * 10) })
    nums.forEach { print(it) }
    println()

    println(nums.filter { it % 2 == 0 })
    println(nums.filterIndexed { index, _ -> index < 2 })
    println(nums.filterNot { it > 3 })
    println(arrayOf(1, null, 3).filterNotNull())

    println(nums.fold(0) { acc, value -> acc + value })
    println(nums.foldIndexed(0) { index, acc, value -> acc + index * value })
    println(nums.reduce { acc, value -> acc + value })
    println(nums.reduceIndexed { index, acc, value -> acc + index + value })
    println(nums.reduceOrNull { acc, value -> acc * value })

    println(nums.find { it > 3 })
    println(nums.findLast { it < 3 })
    println(nums.first())
    println(nums.first { it > 2 })
    println(nums.firstOrNull { it > 100 })
    println(nums.last())
    println(nums.last { it < 3 })
    println(nums.lastOrNull { it > 100 })

    println(nums.count())
    println(nums.count { it % 2 == 1 })
    println(nums.joinToString("-"))
    println(nums.joinToString("-", "[", "]") { "x$it" })
    println(nums.asSequence().map { it + 1 }.toList())

    var sum = 0
    nums.forEach { sum += it }
    println(sum)

    val doubles = arrayOf(1.0, 2.5, 3.5)
    println(doubles.map { it * 2 })
    println(doubles.filter { it > 1.0 })
    println(doubles.fold(0.0) { acc, value -> acc + value })
    println(doubles.reduce { acc, value -> acc + value })
    println(doubles.joinToString(", "))

    val chars = arrayOf('a', 'b', 'c')
    println(chars.map { it })
    println(chars.mapIndexed { index, value -> if (index == 0) value else value + 1 })
    println(chars.filter { it > 'a' })
    println(chars.fold("") { acc, value -> acc + value })

    val words = arrayOf("alpha", "beta", "gamma")
    println(words.map { it.uppercase() })
    println(words.filter { it.startsWith("b") })
    println(words.joinToString("/"))

    val empty = emptyArray<Int>()
    println(empty.map { it })
    println(empty.reduceOrNull { acc, value -> acc + value })
    println(empty.firstOrNull())
    println(empty.any { it > 0 })
    println(empty.none { it > 0 })
    println(empty.count())
}

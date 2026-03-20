fun main() {
    // reduceOrNull on non-empty list
    val sum = listOf(1, 2, 3, 4).reduceOrNull { acc, e -> acc + e }
    println(sum)  // 10

    // reduceOrNull on empty list returns null
    val empty = listOf<Int>().reduceOrNull { acc, e -> acc + e }
    println(empty)  // null

    // reduceOrNull with string concatenation
    val concat = listOf("a", "b", "c").reduceOrNull { acc, e -> acc + e }
    println(concat)  // abc

    // reduceOrNull on single-element list returns that element
    val single = listOf(42).reduceOrNull { acc, e -> acc + e }
    println(single)  // 42

    // reduceOrNull with multiplication
    val product = listOf(2, 3, 4).reduceOrNull { acc, e -> acc * e }
    println(product)  // 24

    // reduceOrNull result used with elvis operator
    val withDefault = listOf<Int>().reduceOrNull { acc, e -> acc + e } ?: -1
    println(withDefault)  // -1

    // reduceOrNull on empty string list
    val emptyStr = listOf<String>().reduceOrNull { acc, e -> acc + e }
    println(emptyStr)  // null
}

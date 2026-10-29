fun main() {
    for ((i, v) in listOf("a", "b", "c").withIndex()) println("$i=$v")
    val indexed = listOf("x", "y").withIndex().iterator()
    while (indexed.hasNext()) { val iv = indexed.next(); println("${iv.index}=${iv.value}") }
    for (iv in listOf("p").withIndex()) println(iv)
    println((sequenceOf(1) + sequenceOf(2)).toList())
    println((sequenceOf(1) + 2).toList())
    println((sequenceOf(1) + listOf(2, 3)).toList())
    println((sequenceOf(1) + arrayOf(2, 3)).toList())
    println("abc".slice(1..2))
    println("hello".slice(listOf(0, 2, 4)))
    println("".slice(4..2))
}

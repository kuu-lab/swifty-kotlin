fun main() {
    val items = listOf(2 to "abc", 4 to "x")
    println(items.runningFold(0) { acc, (number, text) -> acc + number * text.length })
    println(items.runningFold(0) { acc, (_, text) -> acc + text.length })
    println(items.runningFold(0) { acc, (number, _) -> acc + number })
    println(items.runningFold(0) { acc, (_, _) -> acc + 1 })
    println(items.fold(0) { acc, (number, text) -> acc + number * text.length })
    println(items.foldRight(0) { (number, text), acc -> acc + number * text.length })
    items.forEachIndexed { index, (number, text) -> println("$index:$number:$text") }
    println(items.zip(listOf(10, 20)) { (number, text), amount -> number + text.length + amount })
    println(items.zip(items) { (number, text), (other, value) -> number + other + text.length + value.length })
    val annotated: (Int, Pair<Int, String>) -> Int =
        { acc: Int, (number, text): Pair<Int, String> -> acc + number + text.length }
    println(annotated(1, 2 to "abc"))
    println(items.runningFold(0) outer@{ acc, (number, text) ->
        items.forEach { (inner, _) -> if (inner < 0) return@outer acc }
        return@outer acc + number * text.length
    })
    val mixed: (Int, Pair<Int, Int>) -> Int =
        { __destructured_1, (a, b) -> __destructured_1 + a + b }
    println(mixed(10, 2 to 3))
    val groups: (Pair<Int, Int>, Pair<Int, Int>) -> Int =
        { (__destructured_1, a), (b, c) -> __destructured_1 + a + b + c }
    println(groups(2 to 3, 4 to 5))
    val __destructured_1 = 10
    println(items.fold(0) { acc, (number, text) -> acc + __destructured_1 + number + text.length })
    println(items.fold("") { acc, (number, _) -> acc + "$__destructured_1:$number;" })
}

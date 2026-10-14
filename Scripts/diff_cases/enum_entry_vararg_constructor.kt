// KUU-2048: varargs must be packed once per entry, with ordinary call semantics.
enum class Choice(val label: String, private vararg val targets: Int) {
    EMPTY("empty"), ONE("one", 1), MANY("many", 1, 2, 3);
    fun array(): IntArray = targets
}

enum class Words(vararg val words: String) {
    EMPTY, ONE("one"), MANY("a", "b", "c"),
    SPREAD(*arrayOf("s", "t")), NAMED(words = arrayOf("n", "m"))
}

enum class Boxes(vararg val items: Any) {
    MIXED(7, "text", true)
}

enum class Defaults(val label: String, vararg val items: Int = intArrayOf(4, 5)) {
    DEFAULT("default"), EMPTY("empty", *intArrayOf()),
    SPREAD("spread", 1, *intArrayOf(2, 3), 4), NAMED(items = intArrayOf(6, 7), label = "named")
}

object SourceArrays {
    val ints = intArrayOf(8, 9)
    val words = arrayOf("u", "v")
}
enum class Copies(vararg val items: Int = SourceArrays.ints) {
    DEFAULT, OTHER_DEFAULT, SPREAD(*SourceArrays.ints), NAMED(items = SourceArrays.ints)
}
enum class ReferenceCopies(vararg val items: String) {
    SPREAD(*SourceArrays.words), NAMED(items = SourceArrays.words)
}

var calls = 0
fun next(): Int { calls++; return calls }
enum class Ordered(val first: Int, vararg val items: Int, val last: Int = first + items.size) {
    A(next(), next(), next()), B(items = intArrayOf(next(), next()), first = next());
    val snapshot = calls
    init { println("init:$first:${items.size}:$last:$snapshot") }
}

fun main() {
    println(Choice.EMPTY.array().size)
    println(Choice.ONE.array().joinToString())
    val array = Choice.MANY.array()
    println(array.joinToString())
    println(array === Choice.MANY.array())
    array[1] = 9
    println(Choice.MANY.array().joinToString())
    println(Words.EMPTY.words.size)
    println(Words.ONE.words.joinToString())
    println(Words.MANY.words.joinToString())
    println(Words.SPREAD.words.joinToString())
    println(Words.NAMED.words.joinToString())
    println(Words.MANY.words === Words.MANY.words)
    println(Boxes.MIXED.items.joinToString())
    println(Defaults.DEFAULT.items.joinToString())
    println(Defaults.EMPTY.items.size)
    println(Defaults.SPREAD.items.joinToString())
    println(Defaults.NAMED.items.joinToString())
    println(Copies.DEFAULT.items === SourceArrays.ints)
    println(Copies.DEFAULT.items === Copies.OTHER_DEFAULT.items)
    println(Copies.SPREAD.items === SourceArrays.ints)
    println(Copies.NAMED.items === SourceArrays.ints)
    SourceArrays.ints[0] = 10
    println(Copies.DEFAULT.items.joinToString())
    println(Copies.SPREAD.items.joinToString())
    println(Copies.NAMED.items.joinToString())
    println(ReferenceCopies.SPREAD.items === SourceArrays.words)
    println(ReferenceCopies.NAMED.items === SourceArrays.words)
    println(calls)
    println(Ordered.A.items.joinToString())
    println(Ordered.B.items.joinToString())
    println(Ordered.A.first)
    println(Ordered.B.first)
    println(calls)
    println(Ordered.A.items === Ordered.A.items)
}

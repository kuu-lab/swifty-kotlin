// KUU-2045: Array<out T>.maxBy selector, empty/singleton, and first-tie contracts.
// Consumer call: https://github.com/xenomachina/xenocom/blob/745f41619f2e230b2705fa50835bb85ea6532963/src/main/kotlin/TextTerm.kt
fun largest(xs: Array<MutableList<String>>): MutableList<String> = xs.maxBy { it.size }

fun largest(xs: List<MutableList<String>>): MutableList<String> = xs.maxBy { it.size }

fun clear(xs: Array<Any?>) { for (i in 1 until 2) xs[i] = null }

fun columnHeight(columns: Array<MutableList<String>>): Int {
    val height = columns.maxBy { it.size }?.size ?: 0
    return height
}

fun projectedLongest(xs: Array<out CharSequence>): CharSequence = xs.maxBy { it.length }

fun earlyReturn(xs: Array<String>): String {
    xs.maxBy { if (it == "stop") return "returned" else it.length }
    return "finished"
}

class Rank(val value: Int) : Comparable<Rank> {
    override fun compareTo(other: Rank): Int = value.compareTo(other.value)
}

fun main() {
    val first = mutableListOf("a", "b")
    val tied = mutableListOf("c", "d")
    val columns = arrayOf(mutableListOf("x"), first, tied)
    println(largest(columns) === first)
    println(columnHeight(columns))
    val listColumns: List<MutableList<String>> = listOf(mutableListOf("x"), first, tied)
    println(largest(listColumns) === first)
    val slots = arrayOf<Any?>("kept", "cleared")
    clear(slots)
    println(slots[0])
    println(slots[1] == null)

    var calls = 0
    try {
        emptyArray<String>().maxBy { calls++; it.length }
        println("missing exception")
    } catch (e: NoSuchElementException) {
        println("empty")
        println(e.message == null)
    }
    println(calls)
    println(arrayOf("only").maxBy { calls++; it.length })
    println(calls)

    var visited = ""
    println(arrayOf("short", "longest", "equal!!").maxBy {
        calls++
        visited += it + ";"
        it.length
    })
    println(calls)
    println(visited)
    println(arrayOf(3, 1, 4, 2).maxBy { -it })
    println(arrayOf("b", "a", "c").maxBy { it })
    println(arrayOf("aa", "bbbb", "cccc").maxBy { Rank(it.length) })
    println(projectedLongest(arrayOf("a", "long", "same")))
    println(arrayOf<String?>("a", null, "bb").maxBy { it?.length ?: 10 } == null)
    val selector: (String) -> Int = { it.length }
    println(arrayOf("x", "yyy", "zz").maxBy(selector))
    println(earlyReturn(arrayOf("go", "stop", "later")))
    try {
        arrayOf("a", "b").maxBy { if (it == "b") throw IllegalStateException("selector") else it.length }
        println("missing selector exception")
    } catch (e: IllegalStateException) {
        println(e.message)
    }
}

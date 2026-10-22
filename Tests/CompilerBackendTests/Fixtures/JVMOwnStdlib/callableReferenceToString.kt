fun top(): Int = 7
fun sum(x: Int, y: String?): Int = x + (y?.length ?: 0)

class Counter(val base: Int) {
    fun add(value: Int): Int = base + value
}

fun String.measure(): Int = length
fun lengths(values: List<Int>): Int = values.size

fun main() {
    println(::top)
    println((::sum).toString())
    val counter = Counter(10)
    println((counter::add).toString())
    println((Counter::add).toString())
    println((String::measure).toString())
    println(("abc"::measure).toString())
    println((::lengths).toString())
}

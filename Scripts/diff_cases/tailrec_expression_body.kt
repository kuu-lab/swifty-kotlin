tailrec fun sum(n: Long, acc: Long): Long = if (n == 0L) acc else sum(n - 1, acc + n)

tailrec fun count(n: Int, acc: Int = 0): Int = when {
    n == 0 -> acc
    else -> count(n - 1, acc + 1)
}

tailrec fun nested(n: Int, acc: Int): Int =
    if (n <= 0) acc
    else if (n % 2 == 0) nested(n - 1, acc + 2)
    else nested(n - 1, acc + 1)

tailrec fun unitLoop(n: Int) { if (n > 0) unitLoop(n - 1) }

fun main() {
    unitLoop(3_000_000)
    println("unit ok")
    println(sum(10_000_000L, 0L))
    println(count(5_000_000))
    println(nested(4_000_000, 0))
}

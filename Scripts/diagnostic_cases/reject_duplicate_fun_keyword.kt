// EXPECT-REJECT
fun tailrec fun tr(n: Int): Int = n
fun main() { println(tr(1)) }

// EXPECT-REJECT
class C { operator fun iterator() = 1 }
fun main() { for (x in C()) println(x) }

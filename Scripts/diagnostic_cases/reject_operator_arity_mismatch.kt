// EXPECT-REJECT
class C {
    operator fun plus(o: C, x: Int) = 1
    operator fun unaryPlus(a: Int) = 1
    operator fun component1(a: Int) = 1
}
fun main() {}

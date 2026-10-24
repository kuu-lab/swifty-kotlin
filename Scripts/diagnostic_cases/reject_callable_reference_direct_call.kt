// EXPECT-REJECT
fun f() = 1
fun main() {
    val s = "x"
    val a = s::length()
    val b = ::f()
    val ok = (s::length)()
}

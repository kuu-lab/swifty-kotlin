// EXPECT-REJECT
// KOTLINC_FLAGS: -Xcollection-literals
class B {
    companion object {
        operator fun of(s: String): B = B()
        operator fun of(a: Int, b: Int): B = B()
    }
}
fun main() {}

// EXPECT-REJECT
open class Outer { open inner class I
    class N : Outer.I()
}
fun main() { }

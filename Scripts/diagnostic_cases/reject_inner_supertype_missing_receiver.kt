// EXPECT-REJECT
open class Outer { open inner class I }
class C : Outer.I()
fun main() { }

// EXPECT-REJECT
open class Outer { open inner class I }
class C : Outer.Missing()
fun main() {}

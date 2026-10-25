// EXPECT-REJECT
class Outer2 { class Nested }
typealias A2 = Outer2
fun main() { A2.Nested() }

fun main() {
    val flag: (Boolean) -> String = { if (it) "T" else "F" }
    println(flag(true) + flag(false))
    @Suppress("UNCHECKED_CAST")
    val wrongFlag = flag as (Any) -> String
    try { println(wrongFlag("wrong")) } catch (e: ClassCastException) { println("flag cast") }

    val amount = 2
    val number: (Int) -> Int = { it + amount }
    println(number(3))
    @Suppress("UNCHECKED_CAST")
    val wrongNumber = number as (Any) -> Int
    try { println(wrongNumber("wrong")) } catch (e: ClassCastException) { println("number cast") }

    val narrow: (Byte) -> Int = { it.toInt() + 1 }
    println(narrow(7))
    val nullable: (Int?) -> String = { it?.toString() ?: "null" }
    println(nullable(null) + "," + nullable(4))
    val floating: (Double) -> Double = { it + 1.0 }
    println(floating(2.5))
}

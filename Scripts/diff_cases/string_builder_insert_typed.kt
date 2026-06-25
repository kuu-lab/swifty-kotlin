fun main() {
    // insert(Int, Char)
    val sb1 = StringBuilder("hello")
    sb1.insert(0, '!')
    println(sb1.toString())

    // insert(Int, Boolean)
    val sb2 = StringBuilder("is ")
    sb2.insert(3, true)
    println(sb2.toString())

    // insert(Int, Int)
    val sb3 = StringBuilder("value: ")
    sb3.insert(7, 42)
    println(sb3.toString())

    // insert(Int, Long)
    val sb4 = StringBuilder("long: ")
    sb4.insert(6, 1234567890123L)
    println(sb4.toString())

    // insert(Int, Float)
    val sb5 = StringBuilder("pi: ")
    sb5.insert(4, 3.14f)
    println(sb5.toString())

    // insert(Int, Double)
    val sb6 = StringBuilder("e: ")
    sb6.insert(3, 2.718)
    println(sb6.toString())

    // insert(Int, String?)
    val sb7 = StringBuilder("ac")
    sb7.insert(1, "b")
    println(sb7.toString())

    // chained inserts
    val sb8 = StringBuilder("bd")
    sb8.insert(0, "a").insert(2, "c")
    println(sb8.toString())
}

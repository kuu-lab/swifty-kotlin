// KUU-2157: user-declared `Int` classifier must shadow the builtin in type refs and constructor calls.
fun host() {
    class Int
    class Holder(vararg val values: Int)
    val holder = Holder(Int(), Int())
    println(holder.values.size)
    val x: Int = Int()
    println(x is Int)
}

fun main() {
    host()
}

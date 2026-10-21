class C(val i: Int)

operator fun C.component1() = i + 1
operator fun C.component2() = i + 2

fun main() {
    var s = ""
    for ((a, b) in arrayOf(C(1), C(10))) { s += "$a:$b;" }
    for ((a, b) in listOf(C(2), C(20))) { s += "$a:$b;" }
    println(s)
}

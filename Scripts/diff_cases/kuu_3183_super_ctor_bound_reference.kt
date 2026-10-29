abstract class Base(val fn: () -> String)

class Outer {
    val ok = "OK"
    inner class Inner : Base(::ok)
}

fun main() {
    println(Outer().Inner().fn())
}

// KUU-1588: anonymous object expressions must support interface delegation.
interface Greeter { fun greet(): String }
class Impl : Greeter { override fun greet() = "hi" }

fun main() {
    val o = object : Greeter by Impl() {}
    println(o.greet())
}

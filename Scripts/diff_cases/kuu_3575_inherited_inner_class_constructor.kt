// KUU-3575: an inherited inner-class constructor is callable on a subclass instance.
abstract class Base {
    inner class Inner {
        fun o() = "O"
        fun k() = "K"
    }
}

class Child : Base()

fun main() {
    println(Child().Inner().o())
}

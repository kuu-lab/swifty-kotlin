sealed class S
class SA(val x: Int) : S()

sealed class Concrete {
    fun answer(): Int = 42
}
class ConcreteChild : Concrete()

sealed interface Marker
class MarkerChild : Marker

fun main() {
    println("ok")
    println(SA(7).x)
    println(ConcreteChild().answer())
    println(MarkerChild() is Marker)
}

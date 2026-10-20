package demo
open class Named { final override fun toString(): String = "inherited" }
data object Child: Named()
sealed interface Result
data object Empty: Result
class Container { data object Nested }
data object Custom { override fun toString(): String = "custom" }
data class Point(val x: Int = 21, val label: String = "answer")
fun main() {
    println(Empty); println(Container.Nested); println(Custom); println(Child)
    println(Empty == Empty)
    println(Empty.hashCode())
    println(Container.Nested.hashCode())
    println(Point()); println(Point(label = "named").copy(x = 42))
}

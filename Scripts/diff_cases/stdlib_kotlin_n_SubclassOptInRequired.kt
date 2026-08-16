@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class Marker

@SubclassOptInRequired(Marker::class)
open class Base

@Marker
class Derived : Base() {
    fun answer() = 42
}

@OptIn(Marker::class)
fun main() {
    println(Derived().answer())
}

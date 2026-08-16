@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class Marker

annotation class Ann(val message: String)
annotation class Inject

@SubclassOptInRequired(Marker::class)
@Ann("regression coverage")
open class Base

@Marker
class Derived : Base() {
    fun answer() = 42
}

class Service @Inject constructor() {
    val port = 8080
}

class Server internal constructor() {
    val port = 80
}

class Container @Ann("x") constructor(val a: Int)

@OptIn(Marker::class)
fun main() {
    println(Derived().answer())
    println(Service().port)
    println(Server().port)
    println(Container(42).a)
}

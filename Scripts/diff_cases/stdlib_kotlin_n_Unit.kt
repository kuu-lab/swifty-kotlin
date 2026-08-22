fun acceptUnit(value: Unit): Unit = value

fun exposeUnitObject(): Any = Unit

fun main() {
    exposeUnitObject()
    println("Unit")
}

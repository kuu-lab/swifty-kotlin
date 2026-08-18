open class Vehicle(val name: String) {
    open fun describe(): String = "Vehicle($name)"
}

fun makeVehicle(name: String): Vehicle = object : Vehicle(name) {
    override fun describe(): String = "Custom($name)"
}

open class Box<V>(val value: V) {
    open fun render(): String = "Box($value)"
}

fun <T> makeBox(value: T, onRender: (T) -> String): Box<T> = object : Box<T>(value) {
    override fun render(): String = onRender(value)
}

fun main() {
    val vehicle = makeVehicle("car")
    println(vehicle.name)
    println(vehicle.describe())

    val box = makeBox(42) { v -> "Rendered($v)" }
    println(box.value)
    println(box.render())
}

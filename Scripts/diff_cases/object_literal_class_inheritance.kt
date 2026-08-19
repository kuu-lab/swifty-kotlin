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

// Expression-bodied function whose body is an object expression starting on
// the *next* line -- matching upstream kotlin-stdlib's actual formatting
// style for e.g. Delegates.observable.
open class Wrapped(val tag: String) {
    open fun label(): String = "Wrapped($tag)"
}

fun makeWrapped(tag: String): Wrapped =
    object : Wrapped(tag) {
        override fun label(): String = "Multiline($tag)"
    }

// Superclass with multiple constructors: the object expression's super call
// must resolve the overload matching its own arguments, not just the first
// declared constructor.
open class Multi {
    val label: String
    constructor(v: Int) { label = "int:$v" }
    constructor(s: String) { label = "str:$s" }
    open fun describe(): String = "base:$label"
}

fun makeMultiFromInt(v: Int): Multi = object : Multi(v) {
    override fun describe(): String = "over:$label"
}

fun makeMultiFromString(s: String): Multi = object : Multi(s) {
    override fun describe(): String = "over:$label"
}

// Object literal appearing inside a lambda, with the enclosing function's own
// parameter referenced only from the superclass constructor call -- the
// lambda must still capture it, and a lambda body consisting solely of the
// bare object literal expression must not be mis-parsed as a new top-level
// declaration.
open class Factory(val n: Int) { open fun describe(): String = "base:$n" }

fun makeFactory(n: Int): () -> Factory = { object : Factory(n) { override fun describe(): String = "over:$n" } }

fun main() {
    val vehicle = makeVehicle("car")
    println(vehicle.name)
    println(vehicle.describe())

    val box = makeBox(42) { v -> "Rendered($v)" }
    println(box.value)
    println(box.render())

    println(makeWrapped("w").label())

    println(makeMultiFromInt(7).describe())
    println(makeMultiFromString("hi").describe())

    val factory = makeFactory(99)
    println(factory().describe())
}

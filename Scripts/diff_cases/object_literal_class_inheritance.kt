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

// Empty-body object expressions (`object : Base(x) {}`) declare no members at
// all. These used to be routed through a separate lowering path that allocated
// with no `NominalLayout` and never called the superclass constructor, so
// every inherited property read panicked at runtime.
open class Counter(val start: Int) {
    val doubled: Int = start * 2
    open fun describe(): String = "Counter($start,$doubled)"
}

fun makeCounter(start: Int): Counter = object : Counter(start) {}

// Same shape with *no* constructor arguments: the base's own property
// initializer still only runs if the superclass constructor is invoked, which
// the empty-body path skipped regardless of whether arguments were present.
open class Fixed {
    val answer: Int = 42
    open fun describe(): String = "Fixed($answer)"
}

fun makeFixed(): Fixed = object : Fixed() {}

// Empty body with an interface supertype, with a generic superclass, with a
// multi-argument header, and with a class + interface header.
interface Tagged

open class Holder<V>(val item: V)

open class Two(val a: Int, val b: String)

fun makeTagged(): Tagged = object : Tagged {}

fun makeHolder(v: Int): Holder<Int> = object : Holder<Int>(v) {}

fun makeTwo(): Two = object : Two(1, "two") {}

fun makeBoth(n: Int): Counter = object : Counter(n), Tagged {}

// Empty body inside a lambda, with the enclosing function's parameter
// referenced only from the superclass constructor call -- the lambda must
// still capture it even though the literal has no member bodies to scan.
fun makeCounterLater(start: Int): () -> Counter = { object : Counter(start) {} }

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

    val counter = makeCounter(5)
    println(counter.start)
    println(counter.doubled)
    println(counter.describe())

    val fixed = makeFixed()
    println(fixed.answer)
    println(fixed.describe())

    val anyTagged: Any = makeTagged()
    println(anyTagged is Tagged)

    println(makeHolder(8).item)

    val two = makeTwo()
    println(two.a)
    println(two.b)

    val both = makeBoth(3)
    println(both.describe())
    println(both is Tagged)

    println(makeCounterLater(11)().doubled)
}

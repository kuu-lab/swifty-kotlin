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

// An object literal's members are re-parsed from their own token slice, and
// every semicolon used to be stripped first to drop the separator between
// members -- which also removed the statement separators inside a member's own
// body, so a single-line multi-statement body failed to type-check.
open class Ticker(val step: Int) {
    open fun tick(): Int = step
    open fun report(): String = "base"
}

fun makeTicker(step: Int): Ticker = object : Ticker(step) {
    var seen = 0
    val viaLambda: Int = run { val one = 1; one + step }
    override fun tick(): Int { seen = seen + step; return seen }
    fun doubled(): Int { val half = seen; return half * 2 }
    override fun report(): String = "" + doubled() + "/" + viaLambda
}

// Custom accessors on an object expression's properties. Sema used to visit
// only a property's initializer, so identifiers inside a getter/setter body got
// no symbol binding and lowered to `unit`; the implicit-receiver read path also
// loaded a computed property's (never-written) instance slot instead of calling
// its accessor; and no `set` accessor was emitted at all.
open class Stepper(val step: Int) {
    open fun report(): String = "base"
}

fun makeStepper(s: Int): Stepper = object : Stepper(s) {
    val seed: Int = 7
    val fromSibling: Int get() = seed + 1
    val fromInherited: Int get() = step * 2
    var backing: Int = 0
    var viaSetter: Int
        get() = backing * 10
        set(v) { backing = v + 1 }
    var viaField: Int = 0
        get() = field * 100
        set(v) { field = v + 2 }
    override fun report(): String {
        viaSetter = 3
        viaField = 1
        return "" + fromSibling + "/" + fromInherited + "/" + viaSetter + "/" + viaField
    }
}

// An outer local referenced only from an accessor body, both directly and with
// the literal wrapped in a lambda: the accessor is its own KIR function, so the
// value has to be captured into an instance field and read back out.
fun makeCaptured(x: Int): Stepper = object : Stepper(0) {
    val tripled: Int get() = x * 3
    override fun report(): String = "" + tripled
}

fun makeCapturedLater(x: Int): () -> Stepper = { object : Stepper(0) {
    val tripled: Int get() = x * 3
    override fun report(): String = "" + tripled
} }

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

    val ticker = makeTicker(4)
    println(ticker.tick())
    println(ticker.tick())
    println(ticker.report())

    val stepper = makeStepper(4)
    println(stepper.report())

    println(makeCaptured(5).report())
    println(makeCapturedLater(6)().report())
}

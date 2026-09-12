// Error cases for abstract class instantiation (KSWIFTK-SEMA-0310..0313)

abstract class Animal {
    abstract fun speak(): String
}

interface Flyable {
    fun fly(): String
}

abstract class Vehicle {
    abstract val speed: Int
    fun describe() = "speed=$speed"
}

fun main() {
    // ERROR: Cannot instantiate abstract class
    val a = Animal()  // KSWIFTK-SEMA-0310: cannot create an instance of abstract class 'Animal'

    // ERROR: Cannot instantiate interface
    val f = Flyable()  // KSWIFTK-SEMA-0311: interface 'Flyable' does not have constructors

    // ERROR: Cannot instantiate abstract class with constructor args
    val v = Vehicle()  // KSWIFTK-SEMA-0310: cannot create an instance of abstract class 'Vehicle'

    // ERROR: Subclass that does not implement all abstract members is still abstract
    open class PartialImpl : Animal() {
        // Missing override of speak()
    }
    val p = PartialImpl()  // KSWIFTK-SEMA-0312: class 'PartialImpl' is not abstract and does not implement abstract member 'speak()'
}

// KSP-CAP-018: an object expression is always concrete, so it must implement
// every inherited abstract member. These went unchecked entirely -- the named
// nominal check runs during header validation, before an object literal's
// symbol exists.

// ERROR: object expression inheriting abstract class without implementing members
val bad = object : Animal() {}  // KSWIFTK-SEMA-ABSTRACT: must override abstract member 'speak'

// ERROR: same for an unimplemented interface member, with a non-empty body
val badInterface = object : Flyable {
    val unrelated: Int = 1
}  // KSWIFTK-SEMA-ABSTRACT: must override abstract member 'fly'

// OK: implementing the member satisfies the contract
val good = object : Animal() {
    override fun speak(): String = "meow"
}

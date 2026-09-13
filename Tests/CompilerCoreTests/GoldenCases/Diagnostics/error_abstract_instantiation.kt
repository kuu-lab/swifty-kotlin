// Error cases for abstract class instantiation (KSWIFTK-SEMA-ABSTRACT / KSWIFTK-SEMA-0023)

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
    val a = Animal()  // KSWIFTK-SEMA-ABSTRACT: cannot create an instance of abstract class 'Animal'

    // ERROR: Cannot instantiate interface
    val f = Flyable()  // KSWIFTK-SEMA-0023: unresolved function 'Flyable' (an interface has no constructor to resolve)

    // ERROR: Cannot instantiate abstract class with constructor args
    val v = Vehicle()  // KSWIFTK-SEMA-ABSTRACT: cannot create an instance of abstract class 'Vehicle'

    // ERROR: Subclass that does not implement all abstract members is still abstract
    open class PartialImpl : Animal() {
        // Missing override of speak()
    }
    val p = PartialImpl()  // KSWIFTK-SEMA-0023: unresolved function 'PartialImpl' (class is not abstract and does not implement abstract member 'speak()'; KSwiftK surfaces it as an unresolved constructor)
}

// ERROR: object expression inheriting abstract class without implementing members
val bad = object : Animal() {}  // NOT YET DIAGNOSED: kotlinc errors that '<anonymous>' does not implement 'speak()'; KSwiftK emits nothing

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

// ERROR: object expression inheriting abstract class without implementing members
val bad = object : Animal() {}  // KSWIFTK-SEMA-0313: object is not abstract and does not implement abstract member 'speak()'

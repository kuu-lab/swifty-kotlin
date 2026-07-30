// Error cases for interface default method conflicts (KSWIFTK-SEMA-*)

interface InterfaceA {
    fun greet(): String = "Hello from A"
    fun shared(): String = "A"
}

interface InterfaceB {
    fun greet(): String = "Hello from B"
    fun shared(): String = "B"
}

// ERROR: Class implementing both interfaces with conflicting defaults must override
class ConflictingImpl : InterfaceA, InterfaceB {
    // Missing override of greet() — KSWIFTK-SEMA-0090: class 'ConflictingImpl' must override 'greet()' because it inherits multiple implementations
    // Missing override of shared() — KSWIFTK-SEMA-0090: class 'ConflictingImpl' must override 'shared()' because it inherits multiple implementations
}

// ERROR: Interface property conflict
interface PropA {
    val value: Int get() = 1
}

interface PropB {
    val value: Int get() = 2
}

class PropConflict : PropA, PropB {
    // Missing override of value — KSWIFTK-SEMA-0091: class 'PropConflict' must override 'value' because it inherits multiple implementations
}

// ERROR: Diamond inheritance without resolution
interface Base {
    fun method(): String = "base"
}

interface Left : Base {
    override fun method(): String = "left"
}

interface Right : Base {
    override fun method(): String = "right"
}

class Diamond : Left, Right {
    // Missing override of method() — KSWIFTK-SEMA-0090: class 'Diamond' must override 'method()' because it inherits multiple implementations
}

fun main() {}

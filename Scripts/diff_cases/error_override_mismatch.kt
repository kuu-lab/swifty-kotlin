// Error cases for override mismatches (KSWIFTK-SEMA-*)

open class Base {
    open fun method(): Int = 0
    open val prop: Number = 0
    fun finalMethod(): String = "final"
}

class Child : Base() {
    // ERROR: Return type mismatch in override
    override fun method(): String = "wrong"  // KSWIFTK-SEMA-0030: return type of override is incompatible with base type

    // ERROR: Overriding val with incompatible type
    override val prop: String = "wrong"  // KSWIFTK-SEMA-0031: type of 'prop' is not a subtype of the overridden property type

    // ERROR: Overriding non-open (final) function
    override fun finalMethod(): String = "overriding final"  // KSWIFTK-SEMA-0032: 'finalMethod' hides member but cannot be overridden

    // ERROR: Missing override keyword for shadowing member
    fun anotherMethod(): Int = 1  // OK if not overriding, but below we declare same name in interface
}

interface IBase {
    fun interfaceMethod(): Int
}

class BadImpl : IBase {
    // ERROR: Missing override for interface method
    fun interfaceMethod(): String = "wrong return type"  // KSWIFTK-SEMA-0033: 'interfaceMethod' clashes with method in IBase
}

// ERROR: Override of property with var when base is val
open class PropBase {
    open val readOnly: Int = 0
}

class PropChild : PropBase() {
    override var readOnly: Int = 0  // KSWIFTK-SEMA-0034: var cannot override val
}

fun main() {}

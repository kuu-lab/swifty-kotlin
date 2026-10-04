// Error cases for override mismatches (KSWIFTK-SEMA-*)

open class Base {
    open fun method(): Int = 0
    open val prop: Number = 0
    fun finalMethod(): String = "final"
}

class Child : Base() {
    // ERROR: Return type mismatch in override
    override fun method(): String = "wrong"  // KSWIFTK-SEMA-OVERRIDE-RETURN: override of 'method' has incompatible return type (expected subtype of Int, found String)

    // ERROR: Overriding val with incompatible type
    override val prop: String = "wrong"  // NOT YET DIAGNOSED: kotlinc errors that 'prop: String' is not a subtype of the overridden 'prop: Number'; KSwiftK emits nothing

    // ERROR: Overriding non-open (final) function
    override fun finalMethod(): String = "overriding final"  // KSWIFTK-SEMA-FINAL: 'finalMethod' in 'Base' is final and cannot be overridden

    // This method is not declared in Base, so it is not an override and needs no keyword.
    fun anotherMethod(): Int = 1  // OK: new method, no override required
}

interface IBase {
    fun interfaceMethod(): Int
}

class BadImpl : IBase {
    // ERROR: Missing override for interface method
    fun interfaceMethod(): String = "wrong return type"  // KSWIFTK-SEMA-ABSTRACT on the class line: without `override`, 'interfaceMethod' stays unimplemented
}

// Overriding val with var is explicitly allowed in Kotlin (widening is permitted).
// This is NOT an error:
open class PropBase {
    open val readOnly: Int = 0
}

class PropChild : PropBase() {
    override var readOnly: Int = 0  // OK: widening val -> var is valid in Kotlin
}

// ERROR: Override changes property type to an incompatible (non-subtype) type
open class TypeBase {
    open val count: Number = 0
}

class TypeChild : TypeBase() {
    override val count: String = "wrong"  // NOT YET DIAGNOSED: kotlinc errors that 'count: String' is not a subtype of the overridden 'count: Number'; KSwiftK emits nothing
}

fun main() {}

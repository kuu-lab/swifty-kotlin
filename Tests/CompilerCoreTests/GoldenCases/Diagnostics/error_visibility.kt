// Error cases for visibility violations (KSWIFTK-SEMA-*)

class Container {
    private val secret = "private"
    protected val protectedVal = "protected"
    internal val internalVal = "internal"
    val publicVal = "public"
}

fun main() {
    val c = Container()

    // ERROR: Accessing private member from outside class
    println(c.secret)  // KSWIFTK-SEMA-0040: cannot access 'secret': it is private in 'Container'

    // ERROR: Accessing protected member from non-subclass context
    println(c.protectedVal)  // KSWIFTK-SEMA-0041: cannot access 'protectedVal': it is protected in 'Container'
}

// Private-in-file top-level class: the implicit constructor is accessible
// from unrelated code in the same file (BUG-217). This used to misfire as a
// KSWIFTK-SEMA-0040 private-access violation here.
private class InternalImpl

fun publicApi(): InternalImpl = InternalImpl()

// ERROR: Accessing private constructor
class SingletonLike private constructor() {
    companion object {
        fun create() = SingletonLike()
    }
}

val bad = SingletonLike()  // KSWIFTK-SEMA-0043: cannot access '<init>': it is private in 'SingletonLike'

// ERROR: Private function referenced in public inline function
private fun helper() = 42

inline fun publicInline() = helper()  // KSWIFTK-SEMA-0044: public-api inline function cannot access private function 'helper'

// Diagnostic cases for class supertypes written without the required
// constructor invocation (KSWIFTK-SEMA-0436). kotlinc rejects `class C : Base`
// — a class supertype must be written as `Base(...)`.

open class Base
interface I
enum class Direction { NORTH }

// ERROR: bare builtin class supertype
class BareAny : Any

// ERROR: bare user class supertype
class BareBase : Base

// OK: explicit constructor invocation (even with no arguments)
class CallBase : Base()
class CallAny : Any()

// OK: interface supertypes are listed bare
class ImplementsI : I

// ERROR: bare class supertype in a multi-supertype list
class Multi : I, Base

// ERROR: enum classes report finality instead of the missing-call diagnostic
class FromEnum : Direction

// ERROR: object declarations follow the same rule
object BareObject : Base

// ERROR: anonymous object expressions too
val anonymous = object : Base { }

// ERROR: local classes inside function bodies
fun make() {
    class Local : Base
}

// NOT YET DIAGNOSED: kotlinc reports "an interface cannot extend a class." for
// an interface extending a class; KSwiftK emits nothing.
interface BadInterface : Base

fun main() {}

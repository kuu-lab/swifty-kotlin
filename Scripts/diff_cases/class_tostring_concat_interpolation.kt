// A class's own overridden toString() must be called when the value is
// stringified through the Any-erased `+`/string-template funnel
// (CallLowerer.emitAnyToStringWithNullGuard), not just when toString() is
// called directly. Before the fix, `"x=" + f` and `"x=$f"` rendered the raw
// object handle ("<object 0x...>") instead of the override's result, because
// emitAnyToStringWithNullGuard only special-cased enum classes (BUG-204) and
// fell through to the generic kk_any_to_string path -- which has no notion
// of a user-defined toString() override -- for every other class type.
//
// A polymorphic receiver (base-typed variable holding a derived instance)
// must call the *runtime* type's override via virtual dispatch, not the
// statically-declared class's own toString -- both here and in the
// `println`/`print` rewrite (ConsolePrintLoweringPass), which had the same
// static-dispatch defect for a value whose static type is an open base class.
//
// A data class's synthesized (not source-declared) toString() must be
// called too -- its member-wise rendering ("Point(x=1, y=2)") is already
// reachable via `println`/`print`; `+`/string-template stringification must
// reach the exact same symbol.
//
// Residual gaps deliberately absent from this case (still render the raw
// handle after this fix; a separate, broader issue, not this bug -- see
// BUG-221/BUG-222 in TODO.md):
//   - a value statically typed `Any` (the class type is erased before the
//     rewrite ever sees it)
//   - an object singleton (this fix deliberately only handles `class`)
//   - a subclass that inherits toString() without redeclaring it itself,
//     referenced at its own (sub)type rather than the declaring base type
//     (e.g. a sealed subclass referenced through its abstract base type)
class Foo(val x: Int) {
    override fun toString(): String = "Foo(" + x + ")"
}

@JvmInline
value class Wrapper(val v: Int) {
    override fun toString(): String = "Wrapper<$v>"
}

open class Animal {
    override fun toString(): String = "Animal"
}
class Dog : Animal() {
    override fun toString(): String = "Dog"
}

open class Base {
    override fun toString(): String = "Base!"
}
class Derived : Base()

data class Point(val x: Int, val y: Int)

fun main() {
    val f = Foo(1)
    println("concat=" + f)
    println("interp=$f")
    println(f.toString())

    val nf: Foo? = Foo(2)
    println("nullableNonNull=" + nf)
    val nullFoo: Foo? = null
    println("nullableNull=" + nullFoo)

    val w = Wrapper(9)
    println("value=" + w)

    val a: Animal = Dog()
    println("poly=" + a)
    println(a)
    println(a.toString())

    val based: Base = Derived()
    println("inheritedViaBase=" + based)

    val p: Point? = Point(1, 2)
    println("dataConcat=" + p)
    println("dataInterp=$p")
    val noPoint: Point? = null
    println("dataNull=" + noPoint)
}

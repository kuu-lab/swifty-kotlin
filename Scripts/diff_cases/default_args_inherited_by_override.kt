// KUU-655: an `override` inherits the *base* declaration's default
// parameter values even when the override itself declares none of its own.
// kotlinc accepts and runs all of the calls below; before this fix kswiftc
// rejected every omitted-argument call through an override with
// `KSWIFTK-SEMA-0002: No viable overload found for call.` (a class override),
// and separately failed to link at all for an interface override (no
// `$default` stub was ever generated for an interface method's own default
// value expressions -- a second, independent bug this fix also covers).

// Class override, direct base-type dispatch (KUU-655 primary repro A).
open class A { open fun f(x: Int = 1) = "A$x" }
class B : A() { override fun f(x: Int) = "B$x" }

// Interface override (KUU-655 primary repro B).
interface I { fun m(x: Int = 5): String }
class IC : I { override fun m(x: Int) = "IC$x" }

// Three-level override chain: neither intermediate override declares its
// own default, so the innermost concrete override must still inherit from
// the top of the chain.
open class ChainA { open fun f(x: Int = 1) = "ChainA$x" }
open class ChainB : ChainA() { override fun f(x: Int) = "ChainB$x" }
class ChainC : ChainB() { override fun f(x: Int) = "ChainC$x" }

// `by`-delegation forwarder: the synthesized forwarding method is itself an
// "override" of the delegated interface member with no defaults of its own.
interface Greeter { fun greet(name: String = "World"): String }
class GreeterImpl : Greeter {
    override fun greet(name: String) = "Hello, $name!"
}
class Wrapper(impl: Greeter) : Greeter by impl

// Generic interface base.
interface Container<T> { fun get(index: Int = 0): T }
class StringContainer(val items: List<String>) : Container<String> {
    override fun get(index: Int) = items[index]
}

// Diamond: the override chain passes through an intermediate interface that
// itself declares no members of its own.
interface Left { fun f(x: Int = 1): String }
interface Right : Left
class Diamond : Right {
    override fun f(x: Int) = "Diamond$x"
}

fun main() {
    val a: A = B()
    println(a.f())       // B1
    println(a.f(2))      // B2
    println(B().f())     // B1 -- static receiver type is the subclass
    println(A().f())     // A1

    val i: I = IC()
    println(i.m())        // IC5
    println(IC().m())     // IC5
    println(IC().m(9))    // IC9

    val chainA: ChainA = ChainC()
    println(chainA.f())   // ChainC1
    val chainB: ChainB = ChainC()
    println(chainB.f())   // ChainC1
    println(ChainC().f()) // ChainC1

    val w = Wrapper(GreeterImpl())
    println(w.greet())        // Hello, World!
    println(w.greet("Kuu"))   // Hello, Kuu!

    val c: Container<String> = StringContainer(listOf("a", "b", "c"))
    println(c.get())     // a
    println(c.get(2))    // c

    val d: Left = Diamond()
    println(d.f())        // Diamond1
}

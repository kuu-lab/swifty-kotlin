// KUU-3522: `super.<property>` inside an overriding property accessor
// must bind and dispatch to the named supertype's implementation — for
// getters, setters, and unqualified/qualified super receivers.
var result = "Fail"

interface A {
    var foo: String
        get() = result
        set(value) { result = value }
    fun tag(): String = "A"
}

interface B : A

// The ticket shape: the default accessor implementation is inherited
// through an interface chain (C : B : A).
class C : B {
    override var foo: String
        get() = super.foo
        set(value) { super.foo = value }
}

// Qualified super selects the direct supertype explicitly; B inherits
// the accessor implementations from A.
class Q : B {
    override var foo: String
        get() = super<B>.foo
        set(value) { super<B>.foo = value }
}

// `super.<method>()` shares the same supertype-selection machinery.
class M : B {
    override fun tag() = super.tag()
}

// A concrete superclass property accessed through unqualified super.
abstract class Base {
    open var bar: String = "base"
}

class D : Base() {
    override var bar: String
        get() = "D(" + super.bar + ")"
        set(value) { super.bar = value }
}

fun main() {
    val c = C()
    c.foo = "OK"
    println(c.foo)

    val q = Q()
    q.foo = "QED"
    println(q.foo)

    println(M().tag())

    val d = D()
    d.bar = "stored"
    println(d.bar)
}

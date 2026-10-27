open class Base(val s: String)

object Host {
    class Derived : Base(this.foo())
    class Secondary : Base {
        constructor() : super(this.foo())
    }
    class SelfDelegating : Base {
        val tag: String
        constructor(v: String) : super(v) { tag = v }
        constructor() : this(this.foo())
    }
    object Inner : Base(this.foo())
    class Labeled : Base(this@Host.foo())
    fun foo() = "OK"
}

object Outer {
    object Innermost {
        fun foo() = "DEEP"
        class Nested : Base(this.foo())
    }
}

fun main() {
    println(Host.Derived().s)
    println(Host.Secondary().s)
    println(Host.SelfDelegating().s)
    println(Host.Inner.s)
    println(Host.Labeled().s)
    println(Outer.Innermost.Nested().s)
}

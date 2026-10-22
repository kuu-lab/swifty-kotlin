import kotlin.properties.Delegates

open class A {
    public var K: String by Delegates.observable("O") { prop, old, new -> }
        protected set
}
class B : A() {
    init { K = "K" }
}
class C : A() {
    init { this.K = "thisK" }
}

open class P {
    var V: String by Delegates.observable("") { prop, old, new -> }
        private set

    init { V = "pv" }

    fun bump() { V += "!" }
}

var T: String by Delegates.observable("") { prop, old, new -> }
    private set

fun main() {
    val b = B()
    println(b.K)
    println(C().K)
    val p = P()
    println(p.V)
    p.bump()
    println(p.V)
    T = "tv"
    println(T)
}

open class A(val s: String) {
    open inner class B(val t: String) {
        fun v() = s + t
    }
}

class C : A("x") {
    fun implicitReceiver() = B("0").v()
    fun superReceiver() = super.B("1").v()
    fun otherOuter() = A("y").B("2").v()
    fun thisReceiver() = this.B("3").v()
    fun labeledThis() = this@C.B("4").v()

    inner class D {
        fun viaOuter() = this@C.B("5").v()
        fun implicitOuter() = B("6").v()
    }
}

fun main() {
    val c = C()
    println(c.implicitReceiver())
    println(c.superReceiver())
    println(c.otherOuter())
    println(c.thisReceiver())
    println(c.labeledThis())
    println(c.D().viaOuter())
    println(c.D().implicitOuter())
    println(c.B("7").v())
}

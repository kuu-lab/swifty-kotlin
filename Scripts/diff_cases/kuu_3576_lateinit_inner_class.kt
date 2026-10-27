// KUU-3576 / JetBrains testData codegen/box/innerNested/kt63732.kt:
// a member `fun foo` (or `fun counter`) must not shadow the top-level
// property for property reads and writes inside inner-class inits and
// member bodies.
lateinit var foo: Any
var counter: Int = 0
val top: String = "TOP"
object Obj { const val v = "OBJ" }

class A<T : Any> {
    inner class B(x: T) {
        init { foo = x }
    }
    inner class C(val x: T) {
        fun read(): Any = foo
    }
    fun foo(t: T) {
        object { val something: B = B(t) }
    }
    fun counter(t: Int) = t
    fun top(t: Int) = t
    fun Obj() {}
    fun bump() { counter += 5 }
    fun readCounter(): Int = counter
    fun readTop(): String = top
    fun readObj(): String = Obj.v
}

fun main() {
    A<String>().foo("OK")
    println(foo as String)
    val a = A<String>()
    a.bump()
    println(counter)
    println(a.readCounter())
    println(a.readTop())
    println(a.readObj())
    println(a.C("R").read() as String)
}

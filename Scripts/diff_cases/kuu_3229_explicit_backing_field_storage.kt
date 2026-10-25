// KOTLINC_FLAGS: -Xexplicit-backing-fields
// KUU-3229: a property's explicit `field = ...` backing field must be the
// same storage that compiler-provided accessors and property references
// use — reads previously loaded the property's own (never-written)
// global slot, yielding null/stale values.
val field: String = "OK"

val a: Any
    field = field

// A setter-only custom accessor gives the property a distinct backing
// field too; its compiler-provided getter reads that same storage.
var s = 0
    set(v) { field = v * 2 }

class A {
    val city: List<String>
        field = mutableListOf<String>()

    fun foo() = ::city.invoke()
}

fun bar() {
    val a = A()
    a::city.invoke()
}

fun main() {
    println(a)
    s = 5
    println(s)
    s += 5
    println(s)
    println(A().foo().size)
    val a2 = A()
    println(a2::city.invoke().size)
    println(A::city.invoke(A()).size)
    println(a2::city.get().size)
    bar()
    println("done")
}

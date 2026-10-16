// Regression: a no-space nullable receiver uses the combined `?.` token as
// both the nullable suffix and the extension-property separator.
class A
fun A?.foo() {}
var lastSetValue: Int = 0

var A?.bar: Int
    get() = 42
    set(value) { lastSetValue = value }

interface Holder {
    val stored: Int
}

class Box(override val stored: Int) : Holder

val Holder?.label: Int
    get() = this?.stored ?: -1

val Int?.echo: Int
    get() = this ?: -1

fun box(): String {
    val a = A()
    val aFoo = a::foo
    val A_foo = A::foo
    val nullFoo = null::foo
    val aBar = a::bar
    val A_bar = A::bar
    val nullBar = null::bar
    a.bar = 15
    val holder: Holder? = Box(7)
    val number: Int? = 11
    return if (
        nullFoo != null::foo
            || nullFoo == aFoo
            || nullFoo == A_foo
            || nullBar != null::bar
            || nullBar == aBar
            || nullBar == A_bar
    ) {
        "FAIL"
    } else if (a.bar == 42 && lastSetValue == 15 && holder.label == 7 && number.echo == 11) {
        "OK"
    } else {
        "FAIL"
    }
}

fun main() {
    println(box())
}

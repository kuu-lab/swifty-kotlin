// KUU-3592: invoking an extension-function parameter captured by an anonymous
// object must keep the function-value invoke dispatch through its member body.
class Bar
interface Foo { fun go(x: Bar): String }

fun build(bar: Bar.() -> Unit): Foo = object : Foo {
    override fun go(x: Bar): String { x.bar(); return "OK" }
}

fun main() {
    println(build({}).go(Bar()))
}

// KUU-3181 (JetBrains classes/kt1918): invoking a captured extension-lambda
// parameter through member-call sugar (`recv.fn()` / `recv?.fn()`) inside an
// object literal or local class must load the captured field, not emit a raw
// symbolRef of the enclosing parameter ("Invalid function value" panic).
interface Foo {
    fun xyzzy(x: Any?): String
}
interface Runner {
    fun run(): String
}
class Bar

fun buildFoo(bar: Bar.() -> Unit): Foo = object : Foo {
    override fun xyzzy(x: Any?): String {
        (x as? Bar)?.bar()
        return "OK"
    }
}

fun buildRunner(bar: Bar.() -> Unit): Runner {
    class LocalRunner : Runner {
        override fun run(): String {
            val b = Bar()
            b.bar()
            val nb: Bar? = Bar()
            nb?.bar()
            val nul: Bar? = null
            nul?.bar()
            return "OK"
        }
    }
    return LocalRunner()
}

fun main() {
    println(buildFoo({ println("safe") }).xyzzy(Bar()))
    println(buildRunner({ println("hit") }).run())
}

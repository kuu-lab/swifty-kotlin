import kotlin.ExperimentalContextParameters

@OptIn(ExperimentalContextParameters::class)
context(s: String)
fun foo() = s

fun bar(f: () -> String) = f()

inline fun baz(crossinline f: () -> String) = bar { f() }

@OptIn(ExperimentalContextParameters::class)
context(_: String)
fun qux() = baz { foo() }

@OptIn(ExperimentalContextParameters::class)
fun main() {
    println(context("OK") { qux() })
}

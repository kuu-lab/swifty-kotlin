// KUU-4158: a callable whose return type is `Nothing?` is inhabited by `null`;
// invoking it through the erased FunctionN ABI must deliver `null` (the null
// sentinel), not the Unit zero word which printed as `0`.
fun <T : Any?> run(f: () -> T): T = f()
fun runC(f: () -> Int?): Int? = f()
fun retNull(): Nothing? = null
class Holder { fun get(): Nothing? = null }
fun interface Supplier<T> { fun get(): T }
fun fail(): Nothing = throw RuntimeException("boom")
fun main() {
    println(run { null })
    println(runC { null })
    val l: () -> Nothing? = { null }
    println(l())
    val r: () -> Nothing? = ::retNull
    println(r())
    val hr = Holder()::get
    println(hr())
    println(run(::retNull))
    val s = Supplier<Nothing?> { null }
    println(s.get())
    val s2: Supplier<Nothing?> = Supplier(::retNull)
    println(s2.get())
    val ln: () -> Nothing = { fail() }
    try { ln() } catch (e: Throwable) { println("threw") }
}

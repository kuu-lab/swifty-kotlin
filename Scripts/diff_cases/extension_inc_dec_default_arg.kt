// KUU-3192: `++`/`--` on an extension operator `inc`/`dec` whose parameters
// are all optional must lower to the `<name>$default` stub with the default
// mask, exactly like `a.inc()` — the synthesized call carries no explicit
// arguments, so every parameter is omitted. Emitting a direct call to the
// original symbol instead supplied an incomplete argument list and crashed.
var result = "fail"

class A

operator fun A.inc(s: String = "OK"): A { result = s; return this }
operator fun A.dec(s: String = "KO"): A { result = s; return this }

fun main() {
    var a = A()
    a++
    ++a
    println(result)
    a--
    --a
    println(result)
}

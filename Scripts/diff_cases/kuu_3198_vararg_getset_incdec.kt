// KUU-3198: postfix `++`/`--` on a receiver whose `get`/`set` take a `vararg`
// index list. The reported shape (expression-position `A[i, j, k]++`, the
// JetBrains `increment/classVarargGetSetEvaluationOrder` case) must keep
// evaluating each vararg index once, in order, through get -> inc -> set.
// Additionally, the statement-position form (`A[i, j]++` on its own line)
// must resolve the element's `inc()`/`dec()` — previously it took the builtin
// String `+1` concat path and silently produced a different value.

var log = ""

fun logged(value: String) =
    value.also { log += value }

object A {
    var x = ""
    var gets = ""
    var sets = ""

    operator fun get(vararg va: String): String {
        for (s in va) {
            gets += s
        }
        log += "get;"
        return x
    }

    operator fun set(vararg va: String, value: String) {
        for (s in va) {
            sets += s
        }
        log += "set;"
        x = value
    }
}

operator fun String.inc() = this + logged("inc;")
operator fun String.dec() = this + logged("dec;")

fun box(): String {
    // Expression position (the reported JetBrains shape).
    A.x = "start;"
    val xx = A[logged("1;"), logged("2;"), logged("3;")]++
    if (xx != "start;") return "Failed xx: $xx"
    if (A.x != "start;inc;") return "Failed A.x: ${A.x}"
    if (A.gets != "1;2;3;") return "Failed A.gets: ${A.gets}"
    if (A.sets != "1;2;3;") return "Failed A.sets: ${A.sets}"
    if (log != "1;2;3;get;inc;set;") return "Failed log: $log"

    // Statement position: same vararg get/set must route `++` through
    // `String.inc`, not builtin `+1` concatenation.
    A.x = "s;"
    A.gets = ""
    A.sets = ""
    log = ""
    A[logged("4;"), logged("5;")]++
    if (A.x != "s;inc;") return "Failed stmt A.x: ${A.x}"
    if (A.gets != "4;5;") return "Failed stmt A.gets: ${A.gets}"
    if (A.sets != "4;5;") return "Failed stmt A.sets: ${A.sets}"
    if (log != "4;5;get;inc;set;") return "Failed stmt log: $log"

    // Statement-position `--` must route through `String.dec`.
    A.x = "s;"
    A.gets = ""
    A.sets = ""
    log = ""
    A[logged("6;")]--
    if (A.x != "s;dec;") return "Failed dec A.x: ${A.x}"
    if (A.sets != "6;") return "Failed dec A.sets: ${A.sets}"
    if (log != "6;get;dec;set;") return "Failed dec log: $log"

    return "OK"
}

fun main() {
    println(box())
}

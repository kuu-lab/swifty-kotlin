// KUU-632: `(x as Any).hashCode()` / `kk_any_member_hashCode` reaches the
// runtime Pair/Triple/ObjectBox branches of runtimeAnyHashCode, which must
// accumulate in 32-bit wrapping Int arithmetic like every other structural
// hash branch (List/Set/Map/data class). The element hashCodes below are
// large enough that the 31* combine overflows Int32 mid-computation, so an
// accumulator that only wraps at 64 bits — or never — would diverge here.
//
// A plain (non-data) class's Any.hashCode() is intentionally not diffed:
// KSwiftK hashes it structurally (classID + fields) to stay consistent with
// runtimeValuesEqual's structural `==`, while kotlinc returns a
// per-instance identity hashCode. The value is nondeterministic on JVM, so
// there is nothing stable to compare.

data class TwoFields(val x: String, val y: String)

fun main() {
    // Pair via Any — kk_any_member_hashCode -> runtimeAnyHashCode Pair branch.
    val pair = "abcdef" to "ghijkl"
    println((pair as Any).hashCode())
    println(pair.hashCode())

    val longStrings = Pair("averylongstringvaluethathashesbig", "anotherlongstringvalueforthepair")
    println((longStrings as Any).hashCode())

    // Triple via Any — two nested 31* combines, wraps harder.
    val triple = Triple("abcdef", "ghijkl", "mnopqr")
    println((triple as Any).hashCode())
    println(triple.hashCode())

    // Nested Pair deepens the 31* fold the same way a Triple does.
    val nested = Pair("aaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbb") to "cccccccccccccccc"
    println((nested as Any).hashCode())

    // Data class via Any — RuntimeObjectBox data-class branch, compared
    // against kotlinc's compiler-synthesized hashCode.
    println((TwoFields("abcdef", "ghijkl") as Any).hashCode())
    println(TwoFields("abcdef", "ghijkl").hashCode())

    // Consistency: equal content must hash equally through the Any path,
    // and the Any path must agree with the statically-typed call.
    val a = Pair("xoxoxoxoxoxoxoxoxoxoxoxoxoxoxoxoxoxoxoxo", "yayayayayayayayayayayayayayayayayayayayaya")
    val b = Pair("xoxoxoxoxoxoxoxoxoxoxoxoxoxoxoxoxoxoxoxo", "yayayayayayayayayayayayayayayayayayayayaya")
    println((a as Any).hashCode() == (b as Any).hashCode())
    println((a as Any).hashCode() == a.hashCode())
}

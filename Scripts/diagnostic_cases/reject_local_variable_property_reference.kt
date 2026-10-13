// EXPECT-REJECT
// KUU-1355: `::name` can never denote a local variable or value parameter —
// kotlinc reports "references to variables aren't supported yet". Locals are
// simply invisible to `::` resolution, so a same-named non-local property
// still binds, and local functions remain referenceable.
var shadowed = 1

fun takesParam(x: Int) {
    val p = ::x
}

fun main() {
    var shadowed = 9
    var localVar = 3
    fun localFn() = 0
    val top = ::shadowed
    val fn = ::localFn
    val p = ::localVar
}

// Regression: IntegerNarrowingPass must still run when the only Int
// arithmetic in the module is synthesized by a later lowering pass
// (data class hashCode = a.hashCode() * 31 + b.hashCode()). The user
// code deliberately contains no arithmetic operator so the pre-pipeline
// feature scan sees neither `.binary` nor `kk_op_*` callees.
data class P(val a: Int, val b: Int)

fun main() {
    val p = P(2147483647, 2147483647)
    println(p.hashCode())
}

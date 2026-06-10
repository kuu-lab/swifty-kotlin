// SPEC-NUM-0003: Double/Float relational operators (<, <=, >, >=) must use
// IEEE-754 comparison, where any comparison involving NaN returns false,
// and NaN != NaN returns true.  Lowered to kk_op_dlt/dle/dgt/dge/dne which
// delegate to Swift operators that are IEEE-754 compliant.
fun main() {
    val nan = Double.NaN
    println(nan < 1.0)
    println(1.0 < nan)
    println(nan > 1.0)
    println(1.0 > nan)
    println(nan <= 1.0)
    println(nan >= 1.0)
    // == / != are already correct (false / true):
    println(nan == nan)
    println(nan != nan)
}

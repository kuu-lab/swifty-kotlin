// Candidate-only: These bundled Math methods are unavailable in the JDK 21 reference.
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: java_lang_math_extra_members.expected
fun main() {
    println(Math.asinh(1.0) > 0.0 && Math.acosh(2.0) > 0.0 && Math.atanh(0.5) > 0.0)
    println(Math.powExact(3, 4) == 81)
    println(Math.unsignedPowExact(-1, 1) == -1 && Math.unsignedMultiplyExact(2L, 3L) == 6L)
}

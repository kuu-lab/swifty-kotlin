// Regression for SPEC-NUM-0006: Kotlin's MIN_VALUE toString() must match java.lang.*.
fun main() {
    println(Double.MIN_VALUE)
    println(Float.MIN_VALUE)
}

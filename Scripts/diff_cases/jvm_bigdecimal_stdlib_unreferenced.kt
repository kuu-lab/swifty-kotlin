// DIFF_JVM
// The injected BigDecimal stdlib declarations must not require java.math for
// programs that never reference it.
fun main() = println("ok")

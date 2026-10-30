// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: system_process_start_nanos.expected.stdout
fun main() {
    val startNanos = System.processStartNanos()
    val now = System.nanoTime()
    val kotlinSystemStartNanos = kotlin.system.System.processStartNanos()
    val javaSystemStartNanos = java.lang.System.processStartNanos()
    // processStartNanos must be positive and no greater than current nanoTime
    println(startNanos > 0)
    println(now >= startNanos)
    println(kotlinSystemStartNanos > 0)
    println(javaSystemStartNanos > 0)
}

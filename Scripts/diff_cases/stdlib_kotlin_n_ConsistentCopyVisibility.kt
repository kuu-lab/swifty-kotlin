// Diff regression for kotlin.ConsistentCopyVisibility bundled stdlib source.
@ConsistentCopyVisibility
data class Secret internal constructor(val value: Int)

fun main() {
    val s = Secret(1)
    println(s.value)
    println(s.copy(value = 2).value)
}

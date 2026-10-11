package rejectedcontract
interface Left
interface Right
class Both : Left, Right
fun ambiguous(value: Both): String = "top-both"
class AmbiguousPriority {
    fun ambiguous(value: Left): String = "left"
    fun ambiguous(value: Right): String = "right"
    fun check(value: Both) { ambiguous(value) }
}

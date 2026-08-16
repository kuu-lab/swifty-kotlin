package golden.sema

@ConsistentCopyVisibility
class AnnotatedClass

@ConsistentCopyVisibility
data class PrivateCopy(val value: Int)

fun exerciseCopy() {
    val p = PrivateCopy(1)
    val p2 = p.copy(value = 2)
    println(p2.value)
}

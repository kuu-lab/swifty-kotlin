// KUU-1326: Throwable API parity with Kotlin/JVM.
fun main() {
    val cause = RuntimeException("cause")
    println(NoWhenBranchMatchedException().message)
    println(NoWhenBranchMatchedException(null as String?).message)
    println(NoWhenBranchMatchedException("missing").message)
    val withCause = NoWhenBranchMatchedException(null, cause)
    println(withCause.message)
    println(withCause.cause === cause)
    val explicitMessage = NoWhenBranchMatchedException("explicit", cause)
    println(explicitMessage.message)
    println(explicitMessage.cause === cause)
    val causeOnly = NoWhenBranchMatchedException(cause)
    println(causeOnly.message)
    println(causeOnly.cause === cause)
    println(NoWhenBranchMatchedException(null as Throwable?).message)
    println(NoWhenBranchMatchedException(null, null).cause == null)
}

package golden.sema

fun noArgIllegalAccess(): Exception = IllegalAccessException()
fun messageIllegalAccess(message: String?): Exception = IllegalAccessException(message)

fun noArgInterrupted(): Exception = InterruptedException()
fun messageInterrupted(message: String?): Exception = InterruptedException(message)

fun deprecatedNullPointerAlias(): NullPointerException = KotlinNullPointerException()

fun stringBufferAlias(): kotlin.text.StringBuilder = StringBuffer("x")

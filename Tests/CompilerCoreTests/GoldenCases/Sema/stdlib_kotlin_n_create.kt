package golden.sema
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
fun wrapFailure(exception: Throwable): Any = kotlin.createFailure(exception)

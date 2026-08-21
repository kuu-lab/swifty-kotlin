package golden.sema

fun wrapFailure(exception: Throwable): Any = kotlin.createFailure(exception)

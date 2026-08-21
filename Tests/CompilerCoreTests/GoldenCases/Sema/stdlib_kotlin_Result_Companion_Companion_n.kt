package golden.sema

fun resultSuccess(): Result<Int> = Result.success(42)

fun resultFailure(): Result<String> = Result.failure(RuntimeException("boom"))

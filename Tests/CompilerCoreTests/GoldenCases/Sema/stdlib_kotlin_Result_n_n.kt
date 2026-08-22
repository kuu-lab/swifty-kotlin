package golden.sema

fun resultType(value: Any?): Result<Any?> = runCatching { value }

package golden.sema

fun fromNoArg(): NotImplementedError = NotImplementedError()

fun fromMessage(message: String): NotImplementedError = NotImplementedError(message)

fun catchNotImplemented(error: NotImplementedError): String =
    try { throw error } catch (caught: NotImplementedError) { caught.message ?: "null" }


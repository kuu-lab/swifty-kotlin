import kotlinx.serialization.MissingFieldException

fun missing() = MissingFieldException("field", "Example")

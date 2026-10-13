@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
import kotlinx.serialization.*

class CustomSerializationException(message: String): SerializationException(message)

fun main() {
    val custom = CustomSerializationException("custom")
    check(custom is IllegalArgumentException)
    try { throw custom } catch (e: SerializationException) { check(e.message == "custom") }
    val cause = IllegalStateException("root")
    val empty = SerializationException()
    println("empty:${empty.message == null}:${empty.cause == null}:${empty is IllegalArgumentException}")
    val message = SerializationException("message")
    println("message:${message.message}:${message.cause == null}")
    val both = SerializationException("both", cause)
    println("both:${both.message}:${both.cause === cause}")
    val causeOnly = SerializationException(cause)
    println("cause:${causeOnly.message == cause.toString()}:${causeOnly.cause === cause}")
    val nullCause = SerializationException(null as Throwable?)
    println("null-cause:${nullCause.message == null}:${nullCause.cause == null}")
    try { throw custom } catch (e: IllegalArgumentException) { check(e === custom) }
    val single = MissingFieldException("first", "Example")
    println("single:${single.missingFields}:${single.serialName}:${single.cause == null}")
    println(single.message)
    val fields = mutableListOf("first", "second")
    val multiple = MissingFieldException(fields, "Example")
    println("multiple:${multiple.missingFields}:${multiple.serialName}:${multiple.missingFields === fields}")
    println(multiple.message)
    fields.add("third")
    println("aliased:${multiple.missingFields}")
    val noFields = MissingFieldException(emptyList(), "Example")
    println("empty-fields:${noFields.missingFields}")
    println(noFields.message)
    try { throw single } catch (e: SerializationException) {
        println("caught:${e is MissingFieldException}:${e is IllegalArgumentException}:${e.message == single.message}")
    }
}

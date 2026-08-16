package golden.diagnostics

@kotlin.RequiresOptIn(message = "This is a \"quoted\" phrase")
public annotation class QuotedMessageMarker

@QuotedMessageMarker
fun markedWithQuotedMessage(): Int = 1

fun useQuotedMessage(): Int = markedWithQuotedMessage()

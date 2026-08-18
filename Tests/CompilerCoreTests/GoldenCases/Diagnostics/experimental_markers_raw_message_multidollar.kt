package golden.diagnostics

@kotlin.RequiresOptIn(message = $$"""Uses raw\nline""")
public annotation class MultiDollarRawMessageMarker

@MultiDollarRawMessageMarker
fun markedWithMultiDollarRawMessage(): Int = 1

fun useMultiDollarRawMessage(): Int = markedWithMultiDollarRawMessage()

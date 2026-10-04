package golden.diagnostics

@kotlin.RequiresOptIn(message = """Uses raw\nline""")
public annotation class RawMessageMarker

@RawMessageMarker
fun markedWithRawMessage(): Int = 1

fun useRawMessage(): Int = markedWithRawMessage()

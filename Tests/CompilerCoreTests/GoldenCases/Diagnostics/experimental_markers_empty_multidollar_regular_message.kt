package golden.diagnostics

@kotlin.RequiresOptIn(message = $$"")
public annotation class EmptyMultiDollarRegularMessageMarker

@EmptyMultiDollarRegularMessageMarker
fun markedWithEmptyMultiDollarRegularMessage(): Int = 1

fun useEmptyMultiDollarRegularMessage(): Int = markedWithEmptyMultiDollarRegularMessage()

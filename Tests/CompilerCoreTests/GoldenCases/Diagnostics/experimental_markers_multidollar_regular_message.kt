package golden.diagnostics

@kotlin.RequiresOptIn(message = $$"multi $dollar path\\to")
public annotation class MultiDollarRegularMessageMarker

@MultiDollarRegularMessageMarker
fun markedWithMultiDollarRegularMessage(): Int = 1

fun useMultiDollarRegularMessage(): Int = markedWithMultiDollarRegularMessage()

package golden.diagnostics

@kotlin.RequiresOptIn(message = "say \"hi\"")
public annotation class EndingWithQuoteMarker

@EndingWithQuoteMarker
fun markedWithEndingWithQuote(): Int = 1

fun useEndingWithQuote(): Int = markedWithEndingWithQuote()

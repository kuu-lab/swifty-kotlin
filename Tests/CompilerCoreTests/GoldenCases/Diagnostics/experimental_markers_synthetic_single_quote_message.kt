package golden.diagnostics

@kotlin.native.concurrent.ObsoleteWorkersApi
fun markedWithSyntheticSingleQuoteMessage(): Int = 1

fun useSyntheticSingleQuoteMessage(): Int = markedWithSyntheticSingleQuoteMessage()

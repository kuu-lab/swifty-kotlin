package golden.sema

@kotlin.ExperimentalContextParameters
fun markedWithContextParameters(): Int = 1

@OptIn(kotlin.ExperimentalContextParameters::class)
fun callerOfContextParameters(): Int = markedWithContextParameters()

package golden.diagnostics

@Deprecated("say \"hi\"")
fun oldQuotedMessage(): Int = 1

@Deprecated("line1\nline2")
fun oldNewlineMessage(): Int = 2

fun caller(): Int = oldQuotedMessage() + oldNewlineMessage()

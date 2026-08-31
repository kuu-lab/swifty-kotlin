package kotlin.text

/** Appends a line feed character (`\n`) to this Appendable. */
@SinceKotlin("1.4")
@IgnorableReturnValue
public inline fun Appendable.appendLine(): Appendable = append('\n')

/** Appends a nullable character sequence and a line feed character (`\n`). */
@SinceKotlin("1.4")
@IgnorableReturnValue
public inline fun Appendable.appendLine(value: CharSequence?): Appendable = append(value).appendLine()

/** Appends a character and a line feed character (`\n`). */
@SinceKotlin("1.4")
@IgnorableReturnValue
public inline fun Appendable.appendLine(value: Char): Appendable = append(value).appendLine()

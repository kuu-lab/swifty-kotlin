@file:kotlin.jvm.JvmName("StringsKt")
package kotlin.text

@kotlin.internal.InlineOnly
inline fun Appendable.appendLine(): Appendable = append('\n')!!

@kotlin.internal.InlineOnly
inline fun Appendable.appendLine(value: CharSequence?): Appendable = append(value)!!.append('\n')!!

@kotlin.internal.InlineOnly
inline fun Appendable.appendLine(value: Char): Appendable = append(value)!!.append('\n')!!

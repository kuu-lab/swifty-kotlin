package golden.sema

import kotlin.text.Appendable
import kotlin.text.StringBuilder

fun appendLines(target: Appendable): Appendable {
    target.appendLine()
    target.appendLine(null)
    return target.appendLine('!')
}

fun appendToBuilder(): String {
    val builder = StringBuilder()
    appendLines(builder)
    return builder.toString()
}

package java.lang

/**
 * Source-backed view of one saved native frame. The runtime only records
 * return addresses, so for frames taken from a Throwable `frameText` carries
 * the symbolicated line and the other components stay empty.
 */
public class StackTraceElement(
    private val declaringClassName: String,
    private val methodNameValue: String,
    private val fileNameValue: String?,
    private val lineNumberValue: Int,
    private val frameText: String? = null
) {
    public fun getClassName(): String = declaringClassName

    public fun getMethodName(): String = methodNameValue

    public fun getFileName(): String? = fileNameValue

    public fun getLineNumber(): Int = lineNumberValue

    public override fun toString(): String {
        val text = frameText
        if (text != null) return text
        val location = if (fileNameValue == null) "Unknown Source"
        else if (lineNumberValue >= 0) fileNameValue + ":" + lineNumberValue
        else fileNameValue
        return declaringClassName + "." + methodNameValue + "(" + location + ")"
    }
}

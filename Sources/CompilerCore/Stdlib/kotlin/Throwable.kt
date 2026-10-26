package kotlin

import java.lang.StackTraceElement
import kotlin.internal.KsSymbolName

/**
 * The actual storage is allocated by the runtime as a boxed exception object.
 * Members reach the boxed storage through the small `__kk_throwable_*` accessor
 * bridges below. The mutating / suppressed-list members remain extensions with
 * static dispatch, while the virtual members route through the runtime bridge
 * for boxed Throwable values.
 */
public open class Throwable {
    @KsSymbolName("__kk_throwable_new")
    public constructor()

    @KsSymbolName("__kk_throwable_new")
    public constructor(message: String?)

    @KsSymbolName("__kk_throwable_new_cause")
    public constructor(cause: Throwable?)

    @KsSymbolName("__kk_throwable_new_with_cause")
    public constructor(message: String?, cause: Throwable?)

    protected constructor(
        message: String?,
        cause: Throwable?,
        enableSuppression: Boolean,
        writableStackTrace: Boolean
    ) {
        __kkThrowableSetMessage(this, message)
        __kkThrowableSetCause(this, cause)
        __kkThrowableSetOptions(
            this,
            if (enableSuppression) 1L else 0L,
            if (writableStackTrace) 1L else 0L
        )
    }

    public open val message: String?
        get() = __kkThrowableMessage(this)

    public open val cause: Throwable?
        get() = __kkThrowableCause(this)

    public val suppressed: Array<Throwable>
        get() = __kkThrowableSuppressedRaw(this)

    public fun getStackTrace(): Array<String> = __kkThrowableRawStackFrames(this)

    public override fun toString(): String = __kkThrowableToString(this)
}

public fun Throwable.initCause(cause: Throwable?): Throwable {
    __kkThrowableSetCause(this, cause)
    return this
}

public fun Throwable.addSuppressed(exception: Throwable) {
    if (exception !== this) {
        __kkThrowableAppendSuppressed(this, exception)
    }
}

public fun Throwable.getSuppressed(): Array<Throwable> = __kkThrowableSuppressedRaw(this)

public val Throwable.suppressedExceptions: List<Throwable>
    get() = __kkThrowableSuppressedRaw(this).toList()

/**
 * Saved frames without the leading header line. The runtime captures the trace
 * when the throwable is created, so `fillInStackTrace()` has nothing to refresh
 * and returns the receiver.
 */
public var Throwable.stackTrace: Array<StackTraceElement>
    get() {
        val stored = __kkThrowableStackTrace(this)
        if (stored != null) return stored
        val frames = __kkThrowableRawStackFrames(this)
        val count = if (frames.size > 0) frames.size - 1 else 0
        return Array<StackTraceElement>(count) { i -> StackTraceElement("", "", null, -1, frames[i + 1].removePrefix("\tat ")) }
    }
    set(value) {
        __kkThrowableSetStackTrace(this, value)
    }

public val Throwable.localizedMessage: String?
    get() = this.message

public fun Throwable.fillInStackTrace(): Throwable = this

public fun Throwable.stackTraceToString(): String {
    val lines = mutableListOf<String>()
    collectThrowableTraceLines(this, lines, null)
    return lines.joinToString("\n")
}

private fun collectThrowableTraceLines(
    throwable: Throwable,
    lines: MutableList<String>,
    prefix: String?
) {
    val frames = __kkThrowableRawStackFrames(throwable)
    for (i in 0 until frames.size) {
        val line = if (prefix != null && i == 0) prefix + frames[i] else frames[i]
        lines.add(line)
    }

    val suppressed = throwable.getSuppressed()
    for (i in 0 until suppressed.size) {
        collectThrowableTraceLines(suppressed[i], lines, "Suppressed: ")
    }

    val cause = throwable.cause
    if (cause != null) {
        collectThrowableTraceLines(cause, lines, "Caused by: ")
    }
}

public fun Throwable.printStackTrace() {
    __kkPrintStderr(this.stackTraceToString() + "\n")
}

@KsSymbolName("__kk_throwable_message")
internal external fun __kkThrowableMessage(throwable: Throwable): String?

@KsSymbolName("__kk_throwable_setMessage")
internal external fun __kkThrowableSetMessage(throwable: Throwable, message: String?)

@KsSymbolName("__kk_throwable_cause")
internal external fun __kkThrowableCause(throwable: Throwable): Throwable?

@KsSymbolName("__kk_throwable_setCause")
internal external fun __kkThrowableSetCause(throwable: Throwable, cause: Throwable?)

@KsSymbolName("__kk_throwable_set_options")
internal external fun __kkThrowableSetOptions(
    throwable: Throwable,
    enableSuppression: Long,
    writableStackTrace: Long
)

@KsSymbolName("__kk_throwable_appendSuppressed")
internal external fun __kkThrowableAppendSuppressed(throwable: Throwable, exception: Throwable)

@KsSymbolName("__kk_throwable_suppressedRaw")
internal external fun __kkThrowableSuppressedRaw(throwable: Throwable): Array<Throwable>

@KsSymbolName("__kk_throwable_rawStackFrames")
internal external fun __kkThrowableRawStackFrames(throwable: Throwable): Array<String>

@KsSymbolName("__kk_throwable_stackTrace")
internal external fun __kkThrowableStackTrace(throwable: Throwable): Array<StackTraceElement>?

@KsSymbolName("__kk_throwable_setStackTrace")
internal external fun __kkThrowableSetStackTrace(throwable: Throwable, stackTrace: Array<StackTraceElement>)

@KsSymbolName("__kk_throwable_toString")
internal external fun __kkThrowableToString(throwable: Throwable): String

@KsSymbolName("__kk_printStderr")
internal external fun __kkPrintStderr(message: String)

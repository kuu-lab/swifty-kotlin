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
    collectThrowableTraceLines(this, lines, "", null, emptyList(), mutableListOf())
    return lines.joinToString("\n")
}

/**
 * Length of the common SUFFIX shared by [trace] and [enclosingTrace], compared
 * from the end — the KSwiftK analog of the JVM `printEnclosedStackTrace`
 * frame-counting loop. KSwiftK frames are rendered `"\tat <symbol>"` strings
 * rather than `StackTraceElement`s, so string equality is the available
 * identity; throwables created on the same call path share identical native
 * frame symbols for their common tail.
 */
private fun throwableCommonFrameSuffix(trace: List<String>, enclosingTrace: List<String>): Int {
    var count = 0
    var i = trace.size - 1
    var j = enclosingTrace.size - 1
    while (i >= 0 && j >= 0 && trace[i] == enclosingTrace[j]) {
        count += 1
        i -= 1
        j -= 1
    }
    return count
}

/**
 * Mirrors `java.lang.Throwable#printStackTrace`/`printEnclosedStackTrace`:
 * [indent] is the JVM `prefix` (suppressed children indent one `"\t"` deeper
 * than their parent, cause children keep the parent's indent), [caption] is
 * `"Suppressed: "`/`"Caused by: "` (null for the outermost throwable), and
 * [enclosingTrace] is the parent throwable's `"\tat ..."` lines used to fold
 * the shared tail into a single `"\t... N more"` line.
 */
private fun collectThrowableTraceLines(
    throwable: Throwable,
    lines: MutableList<String>,
    indent: String,
    caption: String?,
    enclosingTrace: List<String>,
    visited: MutableList<Throwable>
) {
    // Mirrors java.lang.Throwable#printEnclosedStackTrace's `dejaVu` identity
    // set: a throwable already emitted anywhere in this traversal — a true
    // cycle or a diamond reachable through two branches — collapses to a
    // single "[CIRCULAR REFERENCE: ...]" line instead of recursing without
    // bound. `===` keeps the check referential so a user-overridden
    // equals() can neither forge nor hide a revisit.
    if (visited.any { it === throwable }) {
        lines.add(indent + (caption ?: "") + "[CIRCULAR REFERENCE: " + throwable.toString() + "]")
        return
    }
    visited.add(throwable)

    val frames = __kkThrowableRawStackFrames(throwable)
    // frames[0] is the rendered header ("<type>: <message>"); the rest are the
    // "\tat ..." lines — the analog of the JVM's StackTraceElement[] trace.
    // A throwable with writableStackTrace=false (or an empty assigned trace)
    // yields no frame lines, but the JVM still prints the caption + header.
    val header = if (frames.isNotEmpty()) frames[0] else throwable.toString()
    lines.add(indent + (caption ?: "") + header)

    val trace = frames.drop(1)
    val shared = throwableCommonFrameSuffix(trace, enclosingTrace)
    val printed = trace.size - shared
    for (i in 0 until printed) {
        lines.add(indent + trace[i])
    }
    if (shared > 0) {
        lines.add(indent + "\t... $shared more")
    }

    val suppressed = throwable.getSuppressed()
    for (i in 0 until suppressed.size) {
        collectThrowableTraceLines(suppressed[i], lines, indent + "\t", "Suppressed: ", trace, visited)
    }

    val cause = throwable.cause
    if (cause != null) {
        collectThrowableTraceLines(cause, lines, indent, "Caused by: ", trace, visited)
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

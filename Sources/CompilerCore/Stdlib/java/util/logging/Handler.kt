package java.util.logging

/** A destination for formatted log records. */
public open class Handler {
    private var configuredLevel: Level = Level.ALL
    private var configuredFormatter: Formatter = SimpleFormatter()
    private var closed = false

    public open fun publish(record: LogRecord) {}
    public open fun flush() {}
    public open fun close() { closed = true }

    public val level: Level get() = configuredLevel
    public fun getLevel(): Level = configuredLevel
    public fun setLevel(level: Level) { configuredLevel = level }

    public val formatter: Formatter get() = configuredFormatter
    public fun getFormatter(): Formatter = configuredFormatter
    public fun setFormatter(formatter: Formatter) { configuredFormatter = formatter }

    public fun isLoggable(record: LogRecord): Boolean =
        !closed && record.level !== Level.OFF && record.level.intValue() >= configuredLevel.intValue()
}

public abstract class Formatter {
    public abstract fun format(record: LogRecord): String

    public open fun formatMessage(record: LogRecord): String = record.message

    public open fun getHead(handler: Handler): String = ""
    public open fun getTail(handler: Handler): String = ""
}

public class SimpleFormatter : Formatter() {
    override fun format(record: LogRecord): String = formatMessage(record) + "\n"
}

public class ConsoleHandler : Handler() {
    override fun publish(record: LogRecord) {
        if (isLoggable(record)) java.lang.System.err.print(formatter.format(record))
    }

    override fun flush() = java.lang.System.err.flush()
}

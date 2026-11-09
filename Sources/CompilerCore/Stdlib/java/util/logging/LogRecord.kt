package java.util.logging

public class LogRecord(public var level: Level, public var message: String) {
    public var loggerName: String? = null
    public var sourceClassName: String? = null
    public var sourceMethodName: String? = null
    public var parameters: Array<Any?>? = null
    public var thrown: Throwable? = null
    public var millis: Long = kotlin.system.System.currentTimeMillis()
    public var sequenceNumber: Long = nextSequenceNumber()

    public fun getLevel(): Level = level
    public fun setLevel(value: Level) { level = value }
    public fun getMessage(): String = message
    public fun setMessage(value: String) { message = value }
    public fun getLoggerName(): String? = loggerName
    public fun setLoggerName(value: String?) { loggerName = value }
    public fun getSourceClassName(): String? = sourceClassName
    public fun setSourceClassName(value: String?) { sourceClassName = value }
    public fun getSourceMethodName(): String? = sourceMethodName
    public fun setSourceMethodName(value: String?) { sourceMethodName = value }
    public fun getParameters(): Array<Any?>? = parameters
    public fun setParameters(value: Array<Any?>?) { parameters = value }
    public fun getThrown(): Throwable? = thrown
    public fun setThrown(value: Throwable?) { thrown = value }
    public fun getMillis(): Long = millis
    public fun setMillis(value: Long) { millis = value }
    public fun getSequenceNumber(): Long = sequenceNumber
    public fun setSequenceNumber(value: Long) { sequenceNumber = value }

    public companion object {
        private var nextSequence = 0L
        private fun nextSequenceNumber(): Long {
            nextSequence += 1L
            return nextSequence
        }
    }
}

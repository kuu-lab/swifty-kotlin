package java.util.logging

/** A log severity level with a name and an integer ranking. */
public class Level private constructor(public val name: String, private val value: Int) {
    public fun intValue(): Int = value

    override fun toString(): String = name

    public companion object {
        public val OFF: Level = Level("OFF", Int.MAX_VALUE)
        public val SEVERE: Level = Level("SEVERE", 1000)
        public val WARNING: Level = Level("WARNING", 900)
        public val INFO: Level = Level("INFO", 800)
        public val CONFIG: Level = Level("CONFIG", 700)
        public val FINE: Level = Level("FINE", 500)
        public val FINER: Level = Level("FINER", 400)
        public val FINEST: Level = Level("FINEST", 300)
        public val ALL: Level = Level("ALL", Int.MIN_VALUE)

        private val knownLevels: List<Level> = listOf(OFF, SEVERE, WARNING, INFO, CONFIG, FINE, FINER, FINEST, ALL)

        public fun parse(name: String): Level {
            for (level in knownLevels) if (level.name == name) return level
            throw IllegalArgumentException("Unknown level: $name")
        }
    }
}

/** A named logger that dispatches records through its handlers and parent logger. */
public class Logger internal constructor(public val name: String) {
    private val handlers = ArrayList<Handler>()
    private var configuredLevel: Level? = null
    private var parentLogger: Logger? = null
    private var parentHandlersEnabled = true

    public fun getName(): String = name

    public val level: Level?
        get() = configuredLevel

    public fun getLevel(): Level? = configuredLevel

    public fun setLevel(level: Level?) {
        configuredLevel = level
    }

    public fun getParent(): Logger? = parentLogger

    public fun setParent(parent: Logger?) {
        parentLogger = parent
    }

    public val useParentHandlers: Boolean
        get() = parentHandlersEnabled

    public fun getUseParentHandlers(): Boolean = parentHandlersEnabled

    public fun setUseParentHandlers(enabled: Boolean) {
        parentHandlersEnabled = enabled
    }

    public fun addHandler(handler: Handler) {
        if (handlers.none { it === handler }) handlers.add(handler)
    }

    public fun removeHandler(handler: Handler) {
        val index = handlers.indexOfFirst { it === handler }
        if (index >= 0) handlers.removeAt(index)
    }

    public fun getHandlers(): Array<Handler> = handlers.toTypedArray()

    public fun isLoggable(level: Level): Boolean {
        if (level === Level.OFF) return false
        var current: Logger? = this
        while (current != null && current.configuredLevel == null) current = current.parentLogger
        val threshold = current?.configuredLevel ?: Level.INFO
        return level.intValue() >= threshold.intValue()
    }

    public fun info(message: String) = log(Level.INFO, message)
    public fun warning(message: String) = log(Level.WARNING, message)
    public fun severe(message: String) = log(Level.SEVERE, message)
    public fun fine(message: String) = log(Level.FINE, message)

    public fun log(level: Level, message: String) {
        if (!isLoggable(level)) return
        val record = LogRecord(level, message)
        record.loggerName = name
        log(record)
    }

    public fun log(level: Level, message: String, thrown: Throwable?) {
        if (!isLoggable(level)) return
        val record = LogRecord(level, message)
        record.loggerName = name
        record.thrown = thrown
        log(record)
    }

    public fun log(record: LogRecord) {
        if (!isLoggable(record.level)) return
        if (record.loggerName == null) record.loggerName = name
        var current: Logger? = this
        var first = true
        while (current != null) {
            for (handler in current.handlers) handler.publish(record)
            if (first && !parentHandlersEnabled) break
            first = false
            current = current.parentLogger
        }
    }

    public fun logp(level: Level, sourceClass: String, sourceMethod: String, message: String) {
        if (!isLoggable(level)) return
        val record = LogRecord(level, message)
        record.loggerName = name
        record.sourceClassName = sourceClass
        record.sourceMethodName = sourceMethod
        log(record)
    }

    public fun entering(sourceClass: String, sourceMethod: String) =
        logp(Level.FINER, sourceClass, sourceMethod, "ENTRY")

    public fun exiting(sourceClass: String, sourceMethod: String) =
        logp(Level.FINER, sourceClass, sourceMethod, "RETURN")

    public fun throwing(sourceClass: String, sourceMethod: String, thrown: Throwable) {
        val record = LogRecord(Level.FINER, "THROW")
        record.loggerName = name
        record.sourceClassName = sourceClass
        record.sourceMethodName = sourceMethod
        record.thrown = thrown
        log(record)
    }

    public companion object {
        private val loggers = mutableMapOf<String, Logger>()
        private var globalLogger: Logger? = null
        private val rootLogger: Logger by lazy {
            Logger("").also { root ->
                root.configuredLevel = Level.INFO
                root.addHandler(ConsoleHandler())
                loggers[""] = root
            }
        }

        public fun getLogger(name: String): Logger {
            if (name.isEmpty()) return rootLogger
            val existing = loggers[name]
            if (existing != null) return existing
            val logger = Logger(name)
            if (name.isNotEmpty()) logger.parentLogger = rootLogger
            loggers[name] = logger
            LogManager.getLogManager().register(logger)
            return logger
        }

        public fun getLogger(name: String, resourceBundleName: String?): Logger = getLogger(name)

        public fun getGlobal(): Logger {
            val existing = globalLogger
            if (existing != null) return existing
            val logger = getLogger("global")
            globalLogger = logger
            return logger
        }
    }
}

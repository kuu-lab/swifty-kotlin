package java.util.logging

/** Registry for logger instances created by the bundled logging facade. */
public class LogManager private constructor() {
    private val loggers = LinkedHashMap<String, Logger>()

    internal fun register(logger: Logger) {
        if (!loggers.containsKey(logger.name)) loggers[logger.name] = logger
    }

    public fun addLogger(logger: Logger): Boolean {
        if (loggers.containsKey(logger.name)) return false
        loggers[logger.name] = logger
        return true
    }

    public fun getLogger(name: String): Logger? = loggers[name]

    public fun getLoggerNames(): java.util.Enumeration<String> = java.util.Collections.enumeration(loggers.keys)

    public fun reset() {
        for (logger in loggers.values) {
            for (handler in logger.getHandlers()) handler.close()
        }
        loggers.clear()
    }

    public fun getProperty(name: String): String? = null

    public companion object {
        private val manager = LogManager()
        public fun getLogManager(): LogManager = manager
    }
}

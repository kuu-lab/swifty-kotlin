package java.util.logging

/** A named logger that writes messages to the native process error stream. */
public class Logger private constructor(public val name: String) {
    public fun getName(): String = name

    public fun info(message: String) {
        java.lang.System.err.println(message)
    }

    public fun warning(message: String) {
        java.lang.System.err.println(message)
    }

    public fun severe(message: String) {
        java.lang.System.err.println(message)
    }

    public fun fine(message: String) {
        java.lang.System.err.println(message)
    }

    public companion object {
        private val loggers: MutableMap<String, Logger> = mutableMapOf()

        public fun getLogger(name: String): Logger {
            val existing = loggers[name]
            if (existing != null) return existing
            val logger = Logger(name)
            loggers[name] = logger
            return logger
        }
    }
}

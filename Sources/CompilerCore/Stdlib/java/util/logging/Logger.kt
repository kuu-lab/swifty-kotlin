package java.util.logging

/** A log severity level with a name and an integer ranking (JVM `java.util.logging.Level`). */
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
            for (level in knownLevels) {
                if (level.name == name) return level
            }
            throw IllegalArgumentException("Unknown level: $name")
        }
    }
}

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

    public fun log(level: Level, message: String) {
        java.lang.System.err.println(message)
    }

    public companion object {
        private val loggers: MutableMap<String, Logger> = mutableMapOf()
        private var globalLogger: Logger? = null

        public fun getLogger(name: String): Logger {
            val existing = loggers[name]
            if (existing != null) return existing
            val logger = Logger(name)
            loggers[name] = logger
            return logger
        }

        public fun getGlobal(): Logger {
            val existing = globalLogger
            if (existing != null) return existing
            val logger = Logger("global")
            globalLogger = logger
            return logger
        }
    }
}

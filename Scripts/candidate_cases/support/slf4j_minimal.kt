package org.slf4j

// Test-only subset of SLF4J used to exercise logging_basic.kt on the candidate.
public class Logger(private val name: String) {
    private fun write(level: String, message: String) {
        println("$name|$level|$message")
    }

    private fun formatOne(template: String, argument: Any?): String {
        val markerIndex = template.indexOf("{}")
        if (markerIndex < 0) return template
        return template.substring(0, markerIndex) +
            argument.toString() +
            template.substring(markerIndex + 2)
    }

    private fun formatThree(template: String, first: Any?, second: Any?, third: Any?): String {
        return formatOne(formatOne(formatOne(template, first), second), third)
    }

    public fun trace(message: String) {
        write("TRACE", message)
    }

    public fun debug(message: String, argument: Any?) {
        write("DEBUG", formatOne(message, argument))
    }

    public fun info(message: String) {
        write("INFO", message)
    }

    public fun info(message: String, argument: Any?) {
        write("INFO", formatOne(message, argument))
    }

    public fun info(message: String, first: Any?, second: Any?, third: Any?) {
        write("INFO", formatThree(message, first, second, third))
    }

    public fun warn(message: String) {
        write("WARN", message)
    }

    public fun warn(message: String, argument: Any?) {
        write("WARN", formatOne(message, argument))
    }

    public fun error(message: String) {
        write("ERROR", message)
    }
}

public object LoggerFactory {
    public fun getLogger(name: String): Logger = Logger(name)
}

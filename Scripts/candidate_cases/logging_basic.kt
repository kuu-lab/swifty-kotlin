// Candidate-only coverage of the logging calls, backed by a test source fixture.
import org.slf4j.LoggerFactory

class MyService {
    // Use SLF4J's name overload because KSwiftK targets native code, not JVM Class.
    private val logger = LoggerFactory.getLogger("MyService")

    fun greet(name: String) {
        logger.trace("greet called")
        logger.debug("Greeting user: {}", name)
        logger.info("Hello, {}!", name)
        logger.warn("This is a warning: {}", "low disk space")
        logger.error("This is an error message")
    }
}

fun main() {
    val logger = LoggerFactory.getLogger("main")

    logger.info("Application started")
    logger.debug("Debug info: {}", "startup complete")

    val service = MyService()
    service.greet("Kotlin")

    logger.info("Done: {} {} {}", "one", "two", "three")
    logger.warn("Shutting down")
}

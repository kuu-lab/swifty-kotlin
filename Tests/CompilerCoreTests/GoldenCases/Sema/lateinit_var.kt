// KUU-1597 Sema owner: pin lateinit property access and isInitialized reference resolution; initialization failure/state transitions stay in Scripts/diff_cases/lateinit_var.kt.
class Config {
    lateinit var name: String

    fun isReady(): Boolean = ::name.isInitialized

    fun setup() { name = "test" }
}

fun main() {
    val config = Config()
    val initiallyReady: Boolean = config.isReady()
    config.setup()
    val ready: Boolean = config.isReady()
    val name: String = config.name
}

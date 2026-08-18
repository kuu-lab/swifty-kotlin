@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
annotation class ExperimentalSubclassFamily

@SubclassOptInRequired(ExperimentalSubclassFamily::class)
open class BaseSubclassFamily

@OptIn(ExperimentalSubclassFamily::class)
class AllowedSubclassFamily : BaseSubclassFamily()

fun main() {
    println("ok")
}

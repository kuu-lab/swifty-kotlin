package golden.sema

@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
annotation class ExperimentalSubclassFamily

@SubclassOptInRequired(ExperimentalSubclassFamily::class)
open class BaseSubclassFamily

@OptIn(ExperimentalSubclassFamily::class)
class AllowedSubclassFamily : BaseSubclassFamily()

fun acceptsSubclassOptInRequired(value: SubclassOptInRequired?): Int =
    if (value == null) 0 else 1

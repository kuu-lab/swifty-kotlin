package golden.sema

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class Marker

@SubclassOptInRequired(Marker::class)
open class Base

fun useSubclassOptInRequired(x: SubclassOptInRequired?): Int = 0

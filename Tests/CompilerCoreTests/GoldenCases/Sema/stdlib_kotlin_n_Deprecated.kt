package golden.sema

@Deprecated("Use new instead", level = DeprecationLevel.WARNING)
fun oldWarning(): Int = 1

@Deprecated("Use new instead")
fun oldDefaultWarning(): Int = 2

@Deprecated("Use replacement", replaceWith = ReplaceWith("newApi()"))
fun oldWithReplace(): Int = 3

fun newApi(): Int = 4

fun caller(): Int = oldWarning() + oldDefaultWarning() + oldWithReplace() + newApi()

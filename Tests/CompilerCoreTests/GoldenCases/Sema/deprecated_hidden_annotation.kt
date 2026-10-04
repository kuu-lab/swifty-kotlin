package golden.sema

@Deprecated("Use newFun instead", level = DeprecationLevel.HIDDEN)
fun oldFunHidden(): Int = 1

@Deprecated("Use newFun instead")
@DeprecatedSinceKotlin(warningSince = "1.0", errorSince = "2.0", hiddenSince = "2.1")
fun oldFunSinceHidden(): Int = 2

fun newFun(): Int = 3

fun caller(): Int = oldFunHidden() + oldFunSinceHidden() + newFun()

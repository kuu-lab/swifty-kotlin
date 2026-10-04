package golden.sema

@DeprecatedSinceKotlin(warningSince = "1.0", errorSince = "1.1", hiddenSince = "1.2")
class OldClass

@DeprecatedSinceKotlin
fun oldFun() {}

@DeprecatedSinceKotlin
val oldProperty: Int = 1

@DeprecatedSinceKotlin
annotation class OldAnnotation

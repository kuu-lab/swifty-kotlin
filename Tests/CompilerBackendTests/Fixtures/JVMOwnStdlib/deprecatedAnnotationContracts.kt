@Deprecated("class message", ReplaceWith("Fresh()", "sample.Fresh", "sample.Api"))
class Legacy
class LegacyCtor @Deprecated("constructor") constructor()
class HiddenCtor @Deprecated("hidden constructor", level = DeprecationLevel.HIDDEN) constructor()
@Deprecated("hidden class", level = DeprecationLevel.HIDDEN) class HiddenType
@Deprecated("hidden annotation", level = DeprecationLevel.HIDDEN) annotation class HiddenAnnotationType
class Properties {
    @Deprecated("property") val old = 10
    @get:Deprecated("getter") val getter = 11
    @set:Deprecated("setter") var setter = 12
}
@Deprecated("warning") fun warning() = 13
@Deprecated("error", level = DeprecationLevel.ERROR) fun error() = 14
@Deprecated("hidden", level = DeprecationLevel.HIDDEN) fun hidden() = 15
enum class LocalLevel { ENTRY }
fun DeprecationLevel.name() = "extension-level"
fun LocalLevel.name() = "extension-local"
fun printDeprecation(value: Annotation) {
    val annotation = value as Deprecated
    println(annotation.message)
    println(annotation.level.name)
    println(annotation.replaceWith.expression)
    println(annotation.replaceWith.imports.size)
}
@Suppress("DEPRECATION", "DEPRECATION_ERROR")
fun main() {
    printDeprecation(Legacy::class.annotations[0])
    printDeprecation(::warning.annotations[0])
    printDeprecation(::error.annotations[0])
    printDeprecation(Properties::old.annotations[0])
    println(LegacyCtor()::class.simpleName)
    println(warning())
    println(error())
    println(DeprecationLevel.WARNING.name)
    println(DeprecationLevel.ERROR.ordinal)
    println(DeprecationLevel.HIDDEN.name())
    println(LocalLevel.ENTRY.name())
}

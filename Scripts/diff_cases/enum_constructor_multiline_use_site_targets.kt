// Enum constructor parameters may split use-site-target annotations across
// newlines inside one parameter (Wikipedia Theme.kt pattern).
annotation class StyleRes
annotation class StringRes

enum class Theme(
    val marshallingId: Int,
    val tag: String,
    @field:StyleRes @get:StyleRes
    @param:StyleRes val resourceId: Int,
    @field:StringRes
    @get:StringRes @param:StringRes val nameId: Int
) {
    LIGHT(0, "light", 1, 2),
    DARK(1, "dark", 3, 4)
}

fun main() {
    println(Theme.LIGHT.marshallingId)
    println(Theme.DARK.tag)
    println(Theme.LIGHT.resourceId)
    println(Theme.DARK.nameId)
}

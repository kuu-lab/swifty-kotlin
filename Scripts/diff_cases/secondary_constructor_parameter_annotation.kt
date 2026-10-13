// KUU-1920: value-parameter annotations on secondary constructors must stay on parameters.
@Target(AnnotationTarget.VALUE_PARAMETER)
annotation class Language(val value: String, val prefix: String, val suffix: String)

@Target(AnnotationTarget.CONSTRUCTOR)
annotation class ConstructorOnly

class Token private constructor(
    @param:Language("Name", "", "") val name: String,
    val pattern: String
) {
    @ConstructorOnly
    constructor(
        name: String?,
        @Language("RegExp", "", "") pattern: String,
        ignored: Boolean
    ) : this(name ?: "", pattern)
}

fun main() {
    println(Token("num", "[0-9]+", false).name)
}

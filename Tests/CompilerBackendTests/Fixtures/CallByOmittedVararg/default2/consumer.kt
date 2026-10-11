import kotlin.reflect.KFunction

fun main() {
    val strings = ::defaultStringWords
    val nested = ::defaultNestedWords
    val emptyStrings = defaultArray<String>()
    val emptyNested = defaultArray<Array<String>>()
    println("default-captured-string:" + strings.callBy(mapOf(strings.parameters[0] to emptyStrings)))
    println("default-captured-nested:" + nested.callBy(mapOf(nested.parameters[0] to emptyNested)))
}

// KUU-1110: CharDirectionality uses the standard enum API.
fun main() {
    println('a'.directionality)
    println(' '.directionality)
    println(CharDirectionality.UNDEFINED)
    println('a'.directionality.name)
    println('a'.directionality.toString())
    println(CharDirectionality.valueOf("WHITESPACE"))
    println(enumValues<CharDirectionality>().size)
    for (entry in enumValues<CharDirectionality>()) {
        println(entry.name + ":" + entry.ordinal)
        println(CharDirectionality.valueOf(entry.name) == entry)
        println(CharDirectionality.valueOf(entry.name) != entry)
    }
    println('a'.directionality == CharDirectionality.LEFT_TO_RIGHT)
    println('a'.directionality == CharDirectionality.WHITESPACE)
    println('a'.directionality != CharDirectionality.WHITESPACE)
    println(when (' '.directionality) {
        CharDirectionality.WHITESPACE -> "space"
        else -> "other"
    })
}

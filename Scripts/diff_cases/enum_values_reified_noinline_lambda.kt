enum class E { A, B }

class Choice<T>(
    val variants: List<T>,
    val toVariant: (String) -> T,
    val toString: (T) -> String
)

inline fun <reified T : Enum<T>> Choice(
    noinline toVariant: ((String) -> T)? = null,
    noinline toString: (T) -> String = { it.toString().lowercase() }
): Choice<T> {
    return Choice(
        enumValues<T>().toList(),
        toVariant ?: {
            enumValues<T>().find { e -> toString(e).equals(it, ignoreCase = true) }
                ?: throw IllegalArgumentException("No enum constant $it")
        },
        toString
    )
}

fun main() {
    val choice = Choice<E>()
    println(choice.variants)
    println(choice.toVariant("b"))
}

fun <T> genericArrayIdentity(vararg values: T): Array<out T> = values
fun concreteNestedIdentity(vararg values: Array<String>): Array<out Array<String>> = values
fun scalarBoxedIntWords(vararg values: Int?): Int = values.size
fun scalarNullableWords(vararg values: String?): Boolean = values.size == 1 && values[0] == null
fun scalarStringWords(vararg values: String): Int = values.size
fun scalarNestedWords(vararg values: Array<String>): Int = values.size
inline fun inlineDefaultWords(vararg values: String = arrayOf("default")): Array<out String> = values

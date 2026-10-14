object Token
fun name(value: Any): String? = value::class.simpleName
fun main() { println(name(Token)) }

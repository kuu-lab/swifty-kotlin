class Token(val value: Int)
class Holder(val token: Token)

fun Holder.serializer() {}
fun serializer(token: Token): Int = token.value

fun Holder.probe(): Int = serializer(token)

fun main() {
    println(Holder(Token(41)).probe())
}

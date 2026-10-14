// KUU-2145: infix eligibility precedes member and primitive intrinsic priority.
// KOTLINC_FLAGS: -Xjdk-release=17
class Token { fun select(other: Token): String = "member" }
infix fun Token.select(other: Token): String = "extension"
class InfixToken { infix fun select(other: InfixToken): String = "member" }
infix fun InfixToken.select(other: InfixToken): String = "extension"
class ExtensionToken
infix fun ExtensionToken.select(other: ExtensionToken): String = "extension"
infix fun Int.rem(other: Int): Int = 10
infix operator fun Int.minus(other: Int): Int = 20
fun main() {
    println(Token() select Token())
    println(Token().select(Token()))
    println(InfixToken() select InfixToken())
    println(ExtensionToken() select ExtensionToken())
    println(5 rem 2)
    println(5 minus 3)
    println(5.rem(2))
    println(5.minus(3))
}

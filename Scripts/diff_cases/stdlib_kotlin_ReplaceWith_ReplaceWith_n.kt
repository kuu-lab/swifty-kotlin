fun readReplaceWithExpression(replaceWith: kotlin.ReplaceWith): String = replaceWith.expression

fun readReplaceWithImports(replaceWith: kotlin.ReplaceWith): Array<out String> = replaceWith.imports

fun main() {
    println("stdlib_kotlin_ReplaceWith_ReplaceWith_n ok")
}

package golden.sema

fun readReplaceWithExpression(replaceWith: kotlin.ReplaceWith): String = replaceWith.expression

fun readReplaceWithImports(replaceWith: kotlin.ReplaceWith): Array<out String> = replaceWith.imports

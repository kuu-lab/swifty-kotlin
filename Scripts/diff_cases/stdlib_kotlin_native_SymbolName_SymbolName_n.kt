// SKIP-DIFF (DEBT-DIFF-001): kotlin.native APIs require a Kotlin/Native reference target.
@file:OptIn(kotlin.native.SymbolNameIsInternal::class)

package diff

import kotlin.native.SymbolName

fun readSymbolName(symbolName: SymbolName): String = symbolName.name

fun main() {
    println("ok")
}

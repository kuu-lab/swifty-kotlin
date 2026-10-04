@file:OptIn(kotlin.native.SymbolNameIsInternal::class)

package golden.sema

import kotlin.native.SymbolName

fun readSymbolName(symbolName: SymbolName): String = symbolName.name

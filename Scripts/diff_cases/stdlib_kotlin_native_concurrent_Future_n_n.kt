// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent APIs are only available on Kotlin/Native targets.
@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

import kotlin.native.concurrent.Future

fun main() {
    val future: Future<Int>? = null
    println(future == null)
}

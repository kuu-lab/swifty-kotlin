// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent APIs are only available on Kotlin/Native targets.
@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)
@file:Suppress("DEPRECATION_ERROR")

import kotlin.native.concurrent.DetachedObjectGraph
import kotlin.native.concurrent.attach

fun detachedObjectGraphAttach(graph: DetachedObjectGraph<String>): String =
    graph.attach()

fun main() {}

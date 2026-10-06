package golden.sema

@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)
@file:Suppress("DEPRECATION_ERROR")

import kotlin.native.concurrent.DetachedObjectGraph
import kotlin.native.concurrent.attach

fun detachedObjectGraphAttach(graph: DetachedObjectGraph<String>): String =
    graph.attach()

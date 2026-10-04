package golden.diagnostics

import kotlin.ExperimentalContextParameters

class ContextTag(val label: String)

@OptIn(ExperimentalContextParameters::class)
fun useContextHelpers(): String =
    context("one") { contextOf<String>() } +
        context(1, 2, 3, 4, 5, ContextTag("six")) { contextOf<ContextTag>().label }

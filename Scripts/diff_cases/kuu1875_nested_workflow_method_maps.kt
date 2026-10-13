class Solver {
    private class Rule

    private data class Workflow(val name: String, val rules: List<Rule>) {
        fun countRanges(allWorkflows: Map<String, Workflow>, ranges: Map<Char, IntRange>): String =
            allWorkflows.getValue("A").name
    }

    fun solve(): String {
        val workflows = mapOf("in" to Workflow("in", emptyList()))
        return workflows.getValue("in").countRanges(
            workflows.withDefault { Workflow(it, emptyList()) },
            "xmas".associateWith { 1..4000 }
        )
    }
}

fun main() {
    println(Solver().solve())
}

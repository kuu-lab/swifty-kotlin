class Solver {
    private abstract class Module(val name: String, val destinations: List<String>)
    private class A : Module("a", listOf("left"))
    private class B : Module("b", listOf("right"))
    private class C : Module("c", listOf("other"))

    fun solve(): String {
        val modules = listOf(true, false).associate {
            if (it) "a" to A() else "b" to B()
        }
        val annotated: Map<String, Module> = listOf(true, false).associate {
            if (it) "a" to A() else "b" to B()
        }
        val threeWay = listOf(0, 1, 2).associate {
            when (it) {
                0 -> "a" to A()
                1 -> "b" to B()
                else -> "c" to C()
            }
        }
        println(modules.values.joinToString { it.name })
        println(modules.values.joinToString { it.destinations.single() })
        println(annotated.values.joinToString { it.name })
        println(threeWay.values.joinToString { it.name })
        return "ok"
    }
}

fun main() {
    Solver().solve()
}

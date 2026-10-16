// KUU-2427: Keep explicit invoke, ordinary SAM, and function lambda paths working.
fun interface ExplicitInvoke : () -> Int {
    override fun invoke(): Int
}

fun interface OrdinarySam {
    fun run(): Int
}

fun main() {
    val explicit = ExplicitInvoke { 42 }
    val ordinary = OrdinarySam { 7 }
    val function: () -> Int = { 9 }

    println(explicit.invoke())
    println(ordinary.run())
    println(function())
}

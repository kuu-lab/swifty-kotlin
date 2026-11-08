import Testing

extension BundledStdlibExecutionTests {
    /// KUU-4491: `KClass.members` function handles used to record only the
    /// value-parameter arity with no callable metadata, so `call`/`callBy`
    /// rejected the dispatch receiver and `parameters` omitted the INSTANCE
    /// entry. Member handles now seed the same callable-reference metadata
    /// and invoker, so an unbound member takes its receiver as argument 0 —
    /// matching `Owner::name` references and the JVM.
    @Test(arguments: [false, true])
    func classMemberFunctionHandlesAcceptDispatchReceiver(fromArtifact: Bool) throws {
        try compileAndRunKotlin(
            """
            interface Greeter {
                fun greet(name: String): String
            }
            open class Base {
                open fun who(): String = "base"
            }
            class Derived : Base() {
                override fun who(): String = "derived"
            }
            class C : Greeter {
                override fun greet(name: String): String = "hi $name"
                fun add(a: Int, b: Int = 10): Int = a + b
                fun <T> generic(x: T): T = x
                fun varargy(vararg xs: Int): Int = xs.size
                suspend fun susp(): Int = 1
            }
            data class Point(val name: String, var age: Int)

            fun main() {
                val members = C::class.members.filterIsInstance<kotlin.reflect.KFunction<*>>()
                fun find(n: String) = members.first { it.name == n }
                val c = C()
                println(find("greet").call(c, "bob"))
                println(find("add").call(c, 1, 2))
                val addParams = find("add").parameters
                println(find("add").callBy(mapOf(addParams[0] to c, addParams[1] to 1)))
                println(find("generic").call(c, 42))
                println(find("varargy").call(c, intArrayOf(1, 2, 3)))
                addParams.forEach { println("${it.index}:${it.name}:${it.kind}") }
                val baseWho = Base::class.members.first { it.name == "who" }
                println(baseWho.call(Derived()))
                println(baseWho.call(Base()))
                val shapeGreet = Greeter::class.members.filterIsInstance<kotlin.reflect.KFunction<*>>()
                    .first { it.name == "greet" }
                println(shapeGreet.call(c, "zed"))
                try {
                    find("susp").call(c)
                    println("susp-ok")
                } catch (e: Throwable) {
                    println("susp-err")
                }
                // Synthetic componentN members take the receiver the same way.
                val component1 = Point::class.members.first { it.name == "component1" }
                println(component1.call(Point("n", 9)))
                val copy = Point::class.members.first { it.name == "copy" }
                val p = Point("a", 1)
                val copied = copy.call(p, "b", 2) as Point
                println(copied.name)
                println(copied.age)
                println(copied == Point("b", 2))
            }
            """,
            expectedOutput: """
            hi bob
            3
            11
            42
            3
            0:null:INSTANCE
            1:a:VALUE
            2:b:VALUE
            derived
            base
            hi zed
            susp-err
            n
            b
            2
            true
            """ + "\n",
            moduleName: "KUU4491ClassMemberFunctionCall",
            allowDefaultStdlibLibrary: fromArtifact
        )
    }
}

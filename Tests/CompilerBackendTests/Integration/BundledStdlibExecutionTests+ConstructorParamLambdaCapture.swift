import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func nonValConstructorParametersCapturedByLambdas(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            open class IntBase(val transform: (Int) -> Int)
            class Capturing(offset: Int) : IntBase({ it + offset })
            class Secondary : IntBase {
                constructor(offset: Int) : super({ it + offset })
            }
            class Delegating(val transform: (Int) -> Int) {
                constructor(offset: Int) : this(transform = { it + offset })
            }
            class PropertyInit(offset: Int) {
                val f: (Int) -> Int = { it + offset }
            }
            class InitBlock(offset: Int) {
                val f: (Int) -> Int
                init {
                    f = { it + offset }
                }
            }

            fun main() {
                println(Capturing(3).transform(4))
                println(Secondary(3).transform(4))
                println(Delegating(5).transform(6))
                println(PropertyInit(7).f(8))
                println(InitBlock(9).f(10))
            }
            """,
            expectedOutput: "7\n7\n11\n15\n19\n",
            moduleName: "KConstructorParamLambdaCapture",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}

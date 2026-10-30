@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func testStaticStdlibExtensionsPreserveAppendableInterfaceDispatch(
        allowDefaultStdlibLibrary: Bool,
        optimization: Int
    ) throws {
        try compileAndRunKotlin(
            """
            import kotlin.text.Appendable

            class TextBuffer : Appendable {
                private var contents = ""

                override fun append(value: Char): Appendable {
                    contents += value.toString()
                    return this
                }

                override fun append(value: CharSequence?): Appendable {
                    contents += value ?: "null"
                    return this
                }

                override fun append(value: CharSequence?, startIndex: Int, endIndex: Int): Appendable {
                    val text = value?.toString() ?: "null"
                    contents += text.substring(startIndex, endIndex)
                    return this
                }

                override fun toString(): String = contents
            }

            fun <A : Appendable> appendThroughInterface(buffer: A) {
                buffer.append("interface")
            }

            fun main() {
                println(emptyList<Int>().toTypedArray().size)
                println(listOf(1).map { it + 1 }.toTypedArray()[0])
                println(arrayOf(3, 1, 4, 2).maxBy { -it })

                val target = mutableMapOf<Int, Int>()
                target[0] = 1
                println(target[0])

                val buffer = TextBuffer()
                appendThroughInterface(buffer)
                println(buffer.toString())
            }
            """,
            expectedOutput: "0\n2\n1\n1\ninterface\n",
            moduleName: "StaticExtensionInterfaceDispatch",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}

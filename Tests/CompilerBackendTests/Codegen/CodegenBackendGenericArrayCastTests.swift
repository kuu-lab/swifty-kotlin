#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
import Testing

@Suite
struct CodegenBackendGenericArrayCastTests {
    @Test
    func genericArrayCastFromAnyChecksItsRuntimeComponentType() throws {
        let source = """
        class Data(val x: Int)

        fun main() {
            val arr: Any = arrayOf("zzz")
            try {
                val x = (arr as Array<Data>)[0].x
                println("FAIL: $x")
            } catch (e: ClassCastException) {
                println("caught ClassCastException")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenericArrayCastFromAny",
            expected: "caught ClassCastException\n"
        )
    }

    @Test
    func genericArrayCastChecksItsRuntimeComponentType() throws {
        let source = """
        data class Data(val x: String)

        fun main() {
            val strings = arrayOf("zzz")
            try {
                println((strings as Array<Data>)[0].x)
            } catch (e: ClassCastException) {
                println("caught array cast")
            }

            val safe = strings as? Array<Data>
            if (safe == null) println("safe cast rejected")

            val values = arrayOf(Data("ok")) as Array<Data>
            println(values[0].x)

            val emptyStrings = arrayOf<String>()
            try {
                val emptyValues = emptyStrings as Array<Data>
                println(emptyValues.size)
            } catch (e: ClassCastException) {
                println("caught empty array cast")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenericArrayCastComponentCheck",
            expected: "caught array cast\nsafe cast rejected\nok\ncaught empty array cast\n"
        )
    }
}
#endif

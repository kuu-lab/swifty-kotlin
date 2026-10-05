@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendArrayListConstructorTests {
    @Test(arguments: [false, true])
    func rejectsNegativeCapacity(allowDefaultStdlibLibrary: Bool) throws {
        try assertKotlinOutput(
            """
            fun capacity(): Int {
                println("evaluated")
                return -1
            }
            fun main() {
                try {
                    ArrayList<Int>(capacity())
                    println("accepted")
                } catch (e: IndexOutOfBoundsException) {
                    println("wrong exception")
                } catch (e: IllegalArgumentException) {
                    println("rejected")
                } finally {
                    println("finally")
                }
            }
            """,
            moduleName: "ArrayListNegativeCapacity",
            expected: "evaluated\nrejected\nfinally\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test
    func preservesEmptyCapacityAndCopyConstructors() throws {
        try assertKotlinOutput(
            """
            fun main() {
                val empty = ArrayList<Int>()
                val zero = ArrayList<Int>(0)
                val hinted = ArrayList<Int>(4)
                println(empty.size)
                println(zero.size)
                println(hinted.size)
                hinted.add(7)
                println(hinted)
                println(hinted is ArrayList<*>)
                val input = mutableListOf(1, 2)
                val copy = ArrayList(input)
                input.add(3)
                copy.add(4)
                println(copy)
                println(input)
            }
            """,
            moduleName: "ArrayListConstructorBoundaries",
            expected: "0\n0\n0\n[7]\ntrue\n[1, 2, 4]\n[1, 2, 3]\n"
        )
    }
}

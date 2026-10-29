@testable import CompilerCore
import Foundation
#if canImport(Testing)
import Testing


@Suite
struct CodegenBackendCollectionPlusAssignEdgeCasesTests {

    @Test(arguments: [true, false])
    func testCompoundAssignmentUsesRuntimeCollectionBridges(useArtifact: Bool) throws {
        let source = """
        class Registry {
            companion object {
                val list: MutableList<Int> = mutableListOf(1)
                val set: MutableSet<Int> = mutableSetOf(1)
                val booleans: MutableList<Boolean> = mutableListOf()
                init {
                    list += 2
                    list += listOf(3)
                    list -= 1
                    list -= listOf(2)
                    set += 2
                    set += listOf(3)
                    set -= 1
                    set -= listOf(2)
                    booleans += true
                }
            }
        }

        fun main() {
            val list: MutableList<Int> = mutableListOf(1)
            list += 2
            list += listOf(3)
            list -= 1
            list -= listOf(2)
            println(list)

            val set: MutableSet<Int> = mutableSetOf(1)
            set += 2
            set += listOf(3)
            set -= 1
            set -= listOf(2)
            println(set)

            val booleans: MutableList<Boolean> = mutableListOf()
            booleans += true
            println(Registry.list)
            println(Registry.set)
            println(Registry.booleans)
            println(booleans)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RuntimeCollectionCompoundAssign",
            expected: "[3]\n[3]\n[3]\n[3]\n[true]\n[true]\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }

    @Test
    func testCodegenCollectionPlusAssignMutatesMutableCollections() throws {
        let source = """
        fun main() {
            val list = mutableListOf(1)
            list += 2
            list += listOf(3, 4)
            println(list)

            val set = mutableSetOf("a")
            set += "b"
            set += setOf("b", "c")
            println(set)

            val map = mutableMapOf("a" to 1)
            map += ("b" to 2)
            map += mapOf("a" to 9, "c" to 3)
            println(map)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionPlusAssignEdgeCases", expected: "[1, 2, 3, 4]\n[a, b, c]\n{a=9, b=2, c=3}\n")
    }
}
#endif

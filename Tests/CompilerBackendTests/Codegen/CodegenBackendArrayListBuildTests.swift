@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendArrayListBuildTests {
    // Source-injected O2 still reproduces the shared stdlib ABI failure tracked in KUU-969.
    @Test(arguments: [(false, 0), (true, 0), (true, 2)])
    func buildPreservesContentsAndRejectsMutation(allowDefaultStdlibLibrary: Bool, optimization: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        try assertKotlinOutput(
            """
            @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

            fun main() {
                val list = ArrayList<String?>()
                list.add("first")
                list.add(null)
                val built: List<String?> = list.build()
                println(built.size)
                println(built[0])
                println(built[1])
                try {
                    list.add("late")
                    println("add accepted")
                } catch (e: UnsupportedOperationException) {
                    println("add rejected")
                }
                try {
                    list[0] = "changed"
                    println("set accepted")
                } catch (e: UnsupportedOperationException) {
                    println("set rejected")
                }
                try {
                    list.removeAt(0)
                    println("remove accepted")
                } catch (e: UnsupportedOperationException) {
                    println("remove rejected")
                }
                try {
                    list.clear()
                    println("clear accepted")
                } catch (e: UnsupportedOperationException) {
                    println("clear rejected")
                }
                try {
                    list.add(0, "late")
                    println("indexed add accepted")
                } catch (e: UnsupportedOperationException) {
                    println("indexed add rejected")
                }
                try {
                    list.addAll(emptyList<String?>())
                    println("bulk add accepted")
                } catch (e: UnsupportedOperationException) {
                    println("bulk add rejected")
                }
                try {
                    list.addAll(0, emptyList<String?>())
                    println("indexed bulk add accepted")
                } catch (e: UnsupportedOperationException) {
                    println("indexed bulk add rejected")
                }
                try {
                    list.remove("absent")
                    println("remove value accepted")
                } catch (e: UnsupportedOperationException) {
                    println("remove value rejected")
                }
                try {
                    list.remove("first")
                    println("remove present accepted")
                } catch (e: UnsupportedOperationException) {
                    println("remove present rejected")
                }
                try {
                    list.remove(null)
                    println("remove null accepted")
                } catch (e: UnsupportedOperationException) {
                    println("remove null rejected")
                }
                try {
                    list.removeAll(emptyList<String?>())
                    println("bulk remove accepted")
                } catch (e: UnsupportedOperationException) {
                    println("bulk remove rejected")
                }
                try {
                    list.retainAll(listOf("first", null))
                    println("retain accepted")
                } catch (e: UnsupportedOperationException) {
                    println("retain rejected")
                }
                try {
                    list.build()
                    println("second build accepted")
                } catch (e: UnsupportedOperationException) {
                    println("second build rejected")
                }
                println(built.size)
                println(built[0])
                println(built[1])
            }
            """,
            moduleName: "ArrayListInternalBuild",
            expected: "2\nfirst\nnull\nadd rejected\nset rejected\nremove rejected\nclear rejected\n"
                + "indexed add rejected\nbulk add rejected\nindexed bulk add rejected\nremove value rejected\n"
                + "remove present rejected\nremove null rejected\n"
                + "bulk remove rejected\nretain rejected\nsecond build rejected\n2\nfirst\nnull\n",
            optLevel: optLevel,
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [(false, 0), (true, 0), (true, 2)])
    func buildFreezesEmptyArrayList(allowDefaultStdlibLibrary: Bool, optimization: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        try assertKotlinOutput(
            """
            @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

            fun main() {
                val list = ArrayList<Int>()
                val built = list.build()
                println(built.size)
                try {
                    list.add(1)
                    println("accepted")
                } catch (e: UnsupportedOperationException) {
                    println("rejected")
                }
                println(built.size)
            }
            """,
            moduleName: "ArrayListEmptyBuild",
            expected: "0\nrejected\n0\n",
            optLevel: optLevel,
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [(false, 0), (true, 0), (true, 2)])
    func capacityHintsPreserveContentsAndMutability(allowDefaultStdlibLibrary: Bool, optimization: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        try assertKotlinOutput(
            """
            @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

            fun main() {
                val list = ArrayList<Int>()
                list.trimToSize()
                list.ensureCapacity(-1)
                list.add(10)
                list.add(20)
                for (capacity in listOf(Int.MIN_VALUE, -1, 0, 1, 2, 8, 1024)) {
                    list.ensureCapacity(capacity)
                    list.trimToSize()
                    println(list.size)
                    println(list[0])
                    println(list[1])
                }
                list.add(30)
                println(list.size)
                println(list[2])
                list.removeAt(0)
                list.trimToSize()
                println(list.size)
                println(list[0])
                val built = list.build()
                for (capacity in listOf(Int.MIN_VALUE, -1, 0, 1, 2, 8, 1024)) {
                    list.ensureCapacity(capacity)
                    list.trimToSize()
                }
                println(built.size)
                println(built[0])
                println(built[1])
            }
            """,
            moduleName: "ArrayListCapacityMembers",
            expected: String(repeating: "2\n10\n20\n", count: 7) + "3\n30\n2\n20\n2\n20\n30\n",
            optLevel: optLevel,
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}

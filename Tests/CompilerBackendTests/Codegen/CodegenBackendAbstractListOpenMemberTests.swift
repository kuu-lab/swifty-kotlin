#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendAbstractListOpenMemberTests {
    @Test(arguments: [false, true])
    func overridesDispatchThroughAbstractListAndList(useLibrary: Bool) throws {
        let source = """
        class OpenList : AbstractList<Int>() {
            override val size: Int get() = 1
            override fun get(index: Int): Int = 7
            override fun indexOf(element: Int): Int = 101
            override fun lastIndexOf(element: Int): Int = 202
            override fun subList(fromIndex: Int, toIndex: Int): List<Int> = listOf(303)
        }
        fun main() {
            val abstract: AbstractList<Int> = OpenList()
            val list: List<Int> = abstract
            println(abstract.indexOf(7))
            println(abstract.lastIndexOf(7))
            println(abstract.subList(0, 1)[0])
            println(list.indexOf(7))
            println(list.lastIndexOf(7))
            println(list.subList(0, 1)[0])
            println(listOf(7, 8, 7).indexOf(7))
            println(listOf(7, 8, 7).lastIndexOf(7))
            val strings: List<String?> = listOf("a", null, "a")
            println(strings.indexOf("a"))
            println(strings.lastIndexOf("a"))
            println(strings.indexOf(null))
            println(strings.lastIndexOf("missing"))
            val builtin: List<Int> = mutableListOf(7, 8, 7)
            println(builtin.indexOf(7))
            println(builtin.lastIndexOf(7))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "AbstractListOpenDispatch",
            expected: "101\n202\n303\n101\n202\n303\n0\n2\n0\n2\n1\n-1\n0\n2\n",
            allowDefaultStdlibLibrary: useLibrary
        )
    }

    @Test(arguments: [false, true])
    func abstractListSemanticsAndLiveViews(useLibrary: Bool) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = root.appendingPathComponent("Scripts/diff_cases/stdlib_kotlin_collections_AbstractList_AbstractList_n.kt")
        let source = try String(contentsOf: fixture, encoding: .utf8)
        try assertKotlinOutput(
            source,
            moduleName: "AbstractListSemantics",
            expected: """
            101
            202
            303
            101
            202
            303
            0
            2
            1
            1
            -1
            -1
            true
            false
            false
            false
            false
            953346
            -1
            -1
            1
            true
            0
            false
            iterator-end
            0
            -1
            false
            iterator-start
            1
            1
            false
            true
            4
            3
            list-iterator-end
            3
            iterator-negative
            iterator-past-end
            sub-negative
            sub-past-end
            sub-reversed
            3
            null
            1
            42
            99
            99
            3
            view-negative
            view-past-end
            0

            """,
            allowDefaultStdlibLibrary: useLibrary
        )
    }
}
#endif

#if canImport(Testing)
import Foundation
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Testing

@Suite
struct CodegenBackendMutableCollectionTypeCheckTests {
    @Test
    func listOfValuesPassJvmErasedMutableListChecks() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 { root.deleteLastPathComponent() }
        let source = try String(contentsOf: root.appendingPathComponent(
            "Scripts/diff_cases/kuu3389_list_of_mutable_list_cast.kt"
        ), encoding: .utf8)
        try assertKotlinOutput(
            source,
            moduleName: "ListOfMutableListCast",
            expected: "true\n[1]\ntrue\n[1]\ntrue\nread-only\n"
        )
    }

    @Test
    func mutableCollectionChecksAndCastsMatchKotlin() throws {
        let source = """
        class ReadOnlyListWrapper : List<String> by ArrayList<String>()
        class MutableListWrapper : MutableList<String> by ArrayList<String>()

        inline fun <reified T> isInstance(value: Any): Boolean = value is T
        inline fun <reified T> cast(value: Any): T = value as T
        inline fun <reified T> safeCast(value: Any): T? = value as? T

        fun main() {
            val readOnly: Any = ReadOnlyListWrapper()
            val mutable: Any = MutableListWrapper()

            println(readOnly is MutableList<*>)
            println(mutable is MutableList<*>)
            println(isInstance<MutableList<*>>(readOnly))
            println(isInstance<MutableList<*>>(mutable))

            try {
                readOnly as MutableList<*>
                println("cast missed")
            } catch (e: ClassCastException) {
                println("cast caught")
            }
            try {
                cast<MutableList<*>>(readOnly)
                println("reified cast missed")
            } catch (e: ClassCastException) {
                println("reified cast caught")
            }
            println((mutable as MutableList<*>).size)
            println(cast<MutableList<*>>(mutable).size)

            println((readOnly as? MutableList<*>) == null)
            println((mutable as? MutableList<*>)?.size)
            println(safeCast<MutableList<*>>(readOnly) == null)
            println(safeCast<MutableList<*>>(mutable)?.size)

            val map = HashMap<String, String>()
            map["key"] = "value"
            val entry: Any = map.entries.first()
            println(entry is MutableMap.MutableEntry<*, *>)
            println(isInstance<MutableMap.MutableEntry<*, *>>(entry))
            println((entry as MutableMap.MutableEntry<String, String>).key)
            println(cast<MutableMap.MutableEntry<String, String>>(entry).key)
            println((entry as? MutableMap.MutableEntry<*, *>)?.value)
            println(safeCast<MutableMap.MutableEntry<*, *>>(entry)?.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MutableCollectionErasedTypeChecks",
            expected:
                "false\ntrue\nfalse\ntrue\ncast caught\nreified cast caught\n0\n0\ntrue\n0\ntrue\n0\ntrue\ntrue\nkey\nkey\nvalue\nvalue\n"
        )
    }
}
#endif

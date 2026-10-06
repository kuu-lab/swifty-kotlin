#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendObjectAbstractCollectionTests {
    @Test(arguments: [false, true])
    func inheritedCollectionMembers(useLibrary: Bool) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = root.appendingPathComponent("Scripts/diff_cases/object_abstract_collection_inherited_members.kt")
        try assertKotlinOutput(
            String(contentsOf: fixture, encoding: .utf8),
            moduleName: "ObjectAbstractCollectionMembers",
            expected: "2\n10\n[0, 10]\n1\n0\n[10]\n2\n1\n[0, 10]\n[3, 4]\ntrue\nfalse\n[5, 6]\ntrue\n2\n{a=7, b=8}\n2\n8\ntrue\n2\n{a=7, b=8}\n",
            allowDefaultStdlibLibrary: useLibrary
        )
    }

    @Test(arguments: [false, true])
    func inheritedPropertyAccessors(useLibrary: Bool) throws {
        let source = """
        abstract class Base {
            abstract val size: Int
            abstract var value: Int
            fun describe(): Int = size + value
        }
        abstract class Middle : Base()
        fun main() {
            val instance = object : Middle() {
                override val size = 2
                override var value = 10
            }
            val base: Base = instance
            println(base.size)
            println(base.value)
            println(base.describe())
            base.value = 20
            println(instance.value)
            println(base.describe())
            val computed: Base = object : Middle() {
                override val size: Int get() = 3
                override var value: Int
                    get() = stored
                    set(v) { stored = v * 2 }
                private var stored = 4
            }
            println(computed.describe())
            computed.value = 5
            println(computed.describe())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "ObjectInheritedPropertyAccessors",
            expected: "2\n10\n12\n20\n22\n7\n13\n",
            allowDefaultStdlibLibrary: useLibrary
        )
    }
}
#endif

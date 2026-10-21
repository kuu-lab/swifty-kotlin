#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func mutableCollectionBulkOverloadsRespectProjectionAndParameterNames(mode: EmitMode) throws {
        let library = try ownStdlibRuntime()
        for source in [
            "fun bad(values: MutableList<*>) { values.addAll(arrayOf(1)) }",
            "fun bad(values: MutableCollection<out Number>) { values.addAll(arrayOf(1)) }",
            "fun bad(values: MutableList<*>) { values.addAll(sequenceOf(1)) }",
            "class Holder<T : Number?>(val values: MutableList<T>); fun bad(h: Holder<*>) { h.values.addAll(sequenceOf(null)) }",
            "class Holder<T : Number?>(val values: MutableList<T>); fun bad(h: Holder<*>) { h.values.addAll(arrayOf<Int?>(null)) }",
            "class Holder<T : Number?>(val values: MutableList<T>); fun bad(h: Holder<in Int>) { h.values.addAll(sequenceOf(null)) }",
            "class Holder<T : Number?>(val values: MutableList<T>); fun bad(h: Holder<*>): Number = h.values[0]",
            "class Holder<T : Number?>(val values: MutableList<T?>); fun bad(h: Holder<*>) { val values = h.values; values.addAll(sequenceOf(null)) }",
            "class Holder<T : Number?>(val values: MutableList<T?>); fun bad(h: Holder<*>) { h.values.addAll(wrong = sequenceOf(null)) }",
            "fun bad(values: MutableList<*>) { values.removeAll(arrayOf(1)) }",
            "fun bad(values: MutableList<Int>) { values.addAll(wrong = arrayOf(1)) }",
            "fun bad(values: MutableList<Int>) { values.addAll(wrong = sequenceOf(1)) }",
            "fun bad(values: MutableList<Int>) { values.removeAll(wrong = arrayOf(1)) }",
        ] {
            try withWorkspace { root in
                let result = try compile(source, root: root, mode: mode, classpath: [library.path])
                #expect(result.0 != 0, "Unexpected acceptance: \(source)")
                #expect(result.1.contains { $0.severity == .error })
                #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
            }
        }
        try withWorkspace { root in
            let result = try compile("""
            fun append(values: MutableList<in Int>) {
                values.addAll(elements = arrayOf(2))
                values.addAll(elements = sequenceOf(3))
                val source: Iterable<Int> = listOf(4)
                values.addAll(elements = source)
            }
            fun MutableList<String>.addAll(elements: Array<String>): Boolean = false
            class Holder<T : Number?>(val values: MutableList<T>)
            class NullableHolder<T : Number?>(val values: MutableList<T?>) { fun elements(): MutableList<T?> = values }
            fun appendNullable(holder: NullableHolder<*>) {
                holder.values.addAll(elements = sequenceOf(null))
                holder.elements().addAll(elements = sequenceOf(null))
            }
            fun appendIn(holder: Holder<in Int?>) {
                holder.values.addAll(elements = sequenceOf(null))
                holder.values.addAll(elements = arrayOf<Int?>(null))
            }
            fun appendEmpty(holder: Holder<*>) { holder.values.addAll(emptySequence<Nothing>()) }
            fun readNullable(holder: Holder<*>): Number? = holder.values[0]
            fun main() {
                val values = mutableListOf(1)
                append(values)
                println(values)
                println(values.removeAll(elements = arrayOf(2)))
                println(values)
                val nullable = NullableHolder<Int>(mutableListOf<Int?>(1))
                appendNullable(nullable)
                println(nullable.values)
                val input = Holder<Int?>(mutableListOf<Int?>(2))
                appendIn(input)
                appendEmpty(input)
                println(input.values)
                println(readNullable(Holder<Int?>(mutableListOf<Int?>(null))))
            }
            """, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-Xverify:all", "-cp", artifact + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == "[1, 2, 3, 4]\ntrue\n[1, 3, 4]\n[1, null, null]\n[2, null, null]\nnull\n")
            #expect(execution.stderr.isEmpty)
            _ = try jvmTool("kotlinc", ["hello.kt", "-d", "official.jar"], root: root)
            let foreign = try java(["-Xverify:all", "-cp", root.appendingPathComponent("official.jar").path + ":" + library.path, "HelloKt"])
            #expect(foreign.stdout == execution.stdout)
            #expect(foreign.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func mutableCollectionBulkCallsPreserveUserExtensions(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("mutableCollectionUserBulkContracts.kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent("mutableCollectionUserBulkContracts.out"), encoding: .utf8)
        try withWorkspace { root in
            let library = try ownStdlibRuntime()
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-Xverify:all", "-cp", artifact + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == expected)
            #expect(execution.stderr.isEmpty)
            _ = try jvmTool("kotlinc", ["hello.kt", "-d", "official.jar"], root: root)
            let foreign = try java(["-Xverify:all", "-cp", root.appendingPathComponent("official.jar").path + ":" + library.path, "HelloKt"])
            #expect(foreign.stdout == expected)
            #expect(foreign.stderr.isEmpty)
        }
    }
}
#endif

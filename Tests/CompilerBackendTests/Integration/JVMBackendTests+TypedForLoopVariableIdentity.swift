#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func typedForDestructuringUsesDeclaredEntryTypes(mode: EmitMode) throws {
        let source = """
        fun describe(x: String): String = "String"
        fun describe(x: Any): String = "Any"
        data class Row(val number: Double, val label: String)

        fun main() {
            for ((k: String, v) in listOf("a" to 1)) { println(k + v) }
            for ((k, v: Int) in mapOf("b" to 2)) { println(k + v) }
            for ((k: Any, _: Int) in listOf("c" to 3)) { println(describe(k)) }
            for ((k: Map<String, Int>?, v: Int) in listOf(mapOf("d" to 4) to 5)) {
                println(k?.get("d"))
                println(v)
            }
            for ((n: Any, k) in listOf(Row(6.0, "e"))) {
                println(n === n)
                println(k)
            }
            for ((i: Any, n: Number) in listOf(1000).withIndex()) {
                println(i === i)
                println(n)
            }
        }
        """
        try withWorkspace { root in
            try runM11(source, expected: "a1\nb2\nAny\n4\n5\ntrue\ne\ntrue\n1000\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [
        ("k: Int, v", #""a" to 1"#, "component1()", "String", "Int"),
        ("k, v: String", #""a" to 1"#, "component2()", "Int", "String"),
        ("_: Int, _", #""a" to 1"#, "component1()", "String", "Int"),
        ("k: String, _", "null as String? to 1", "component1()", "String?", "String"),
    ])
    func typedForDestructuringRejectsIncompatibleEntries(
        entries: String, pair: String, component: String, actual: String, expected: String
    ) throws {
        let source = "fun main() { for ((\(entries)) in listOf(\(pair))) {} }"
        try withWorkspace { root in
            let (status, diagnostics) = try compile(source, root: root, mode: .jvmJar)
            #expect(status != 0)
            let errors = diagnostics.filter { $0.severity == .error }
            #expect(errors.map(\.code) == ["KSWIFTK-SEMA-0468"])
            #expect(errors.first?.message.contains("'\(component)' returns '\(actual)', but '\(expected)' is expected") == true)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func typedForLoopVariableKeepsBoxedIdentity(mode: EmitMode) throws {
        let source = """
        fun main() {
            for (x: Any in doubleArrayOf(1.0, 2.0)) {
                println(x === x)
                println(x !== x)
            }
            for (n: Number in intArrayOf(1, 2)) {
                println(n === n)
            }
            for (y in longArrayOf(3L)) {
                println(y === y)
            }
        }
        """
        let expected = """
        true
        false
        true
        false
        true
        true
        true

        """

        try withWorkspace { root in
            try runM11(source, expected: expected, mode: mode, root: root)
        }
    }
}
#endif

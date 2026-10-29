@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct CodegenBackendEnumVarargConstructionTests {
    @Test
    func defaultsBeyondTheCallABIMaskRemainEvaluated() throws {
        let precedingParameters = (0 ..< 63).map { "p\($0): Int = \($0)" }.joined(separator: ", ")
        try assertKotlinOutput(
            """
            enum class E(\(precedingParameters), vararg val items: Int, val last: Int = 99) {
                A(items = intArrayOf(1, 2))
            }
            fun main() { println(E.A.last); println(E.A.items.joinToString()) }
            """,
            moduleName: "EnumVarargWideDefaults",
            expected: "99\n1, 2\n"
        )
    }

    @Test
    func secondaryConstructorOnlyEnumRetainsBodyInitialization() throws {
        try assertKotlinOutput(
            """
            enum class E {
                A;
                constructor() {}
                init { println("init") }
            }
            fun main() { println(E.A) }
            """,
            moduleName: "EnumSecondaryConstructorInit",
            expected: "init\nA\n"
        )
    }

    @Test(arguments: [false, true], [false, true])
    func matchesJVMStorageAndEvaluation(useArtifact: Bool, optimized: Bool) throws {
        if useArtifact { _ = try testStdlibArtifactPath() }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 { root.deleteLastPathComponent() }
        let source = try String(contentsOf: root.appendingPathComponent(
            "Scripts/diff_cases/enum_entry_vararg_constructor.kt"
        ), encoding: .utf8)
        // Kotlin/JVM 2.3.10, -Xjdk-release=17. Defaults preserve array identity;
        // explicit named/spread arrays are copied, and entries initialize once.
        try assertKotlinOutput(
            source,
            moduleName: "EnumVarargConstruction",
            expected: """
            0
            1
            1, 2, 3
            true
            1, 9, 3
            0
            one
            a, b, c
            s, t
            n, m
            true
            7, text, true
            4, 5
            0
            1, 2, 3, 4
            6, 7
            true
            true
            false
            false
            10, 9
            8, 9
            8, 9
            false
            false
            0
            init:1:2:3:3
            init:6:2:8:6
            2, 3
            4, 5
            1
            6
            6
            true
            """ + "\n",
            optLevel: optimized ? .O2 : .O0,
            allowDefaultStdlibLibrary: useArtifact
        )
    }
}

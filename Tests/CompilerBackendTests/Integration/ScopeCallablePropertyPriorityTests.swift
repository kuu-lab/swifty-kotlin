import Foundation
@testable import CompilerBackend
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct ScopeCallablePropertyPriorityTests {
    private let expected = "16\ngetters:1\n11\n4\n16\n5\n99\n6\n7\n8\n18\n10\nnull\ngetters:1\n13\ngetters:2\n17\n6\n"
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
    private func fixture() throws -> String {
        try String(contentsOf: repository.appendingPathComponent("Scripts/diff_cases/scope_callable_property_priority.kt"), encoding: .utf8)
    }

    @Test(arguments: ["any", "sam", "nominalFunction", "functionSupertype", "functionReferenceSupertype", "callableReferenceSupertype", "callableReference", "boundReference", "unboundReference", "memberLocal", "explicitTypeArguments", "directReceiver", "privateImplicit"])
    func contextualArgumentsAndMemberPriority(_ mode: String) throws {
        let source: String
        let expectedOutput: String
        switch mode {
        case "any":
            source = "class H\nval H.apply: (Any) -> Int get() = { 42 }\nfun main() { println(H().apply {}) }"
            expectedOutput = "42\n"
        case "sam":
            source = "fun interface Action { fun run() }\nclass H\nval H.apply: (Action) -> Int get() = { 42 }\nfun main() { println(H().apply {}) }"
            expectedOutput = "42\n"
        case "nominalFunction":
            source = "class H\nval H.apply: (Function0<Unit>) -> Int get() = { 42 }\nfun main() { println(H().apply {}) }"
            expectedOutput = "42\n"
        case "functionSupertype":
            source = "class H\nval H.apply: (Function<Unit>) -> Int get() = { 42 }\nfun main() { println(H().apply {}) }"
            expectedOutput = "42\n"
        case "functionReferenceSupertype", "callableReferenceSupertype":
            let type = mode == "functionReferenceSupertype" ? "KFunction" : "KCallable"
            source = "import kotlin.reflect.\(type)\nclass H\nfun consume(h: H) { println(7) }\nval H.let: (\(type)<Unit>) -> Int get() = { 42 }\nfun main() { println(H().let(::consume)) }"
            expectedOutput = "42\n"
        case "callableReference":
            source = "class H\nfun consume(h: H) { println(7) }\nval H.let: (() -> Unit) -> Int get() = { 42 }\nfun main() { H().let(::consume) }"
            expectedOutput = "7\n"
        case "boundReference":
            source = """
            class H
            class Consumer { fun consume(h: H) { println(7) } }
            val H.let: (() -> Unit) -> Int get() = { 42 }
            fun main() { val consumer = Consumer(); H().let(consumer::consume) }
            """
            expectedOutput = "7\n"
        case "unboundReference":
            source = """
            class H { fun consume() { println(7) } }
            val H.let: (() -> Unit) -> Int get() = { 42 }
            fun main() { H().let(H::consume) }
            """
            expectedOutput = "7\n"
        case "memberLocal":
            source = """
            class H { val apply: (H.() -> Unit) -> Int get() = { 42 } }
            fun main() {
                fun H.apply(block: H.() -> Unit): Int = 99
                println(H().apply {})
            }
            """
            expectedOutput = "42\n"
        case "explicitTypeArguments":
            source = "class H(val seed: Int) { val apply: (H.() -> Unit) -> Int get() = { 42 } }\nfun main() { println(H(8).apply<H> {}.seed) }"
            expectedOutput = "8\n"
        case "directReceiver":
            source = """
            class H(val seed: Int)
            val H.apply: (H.() -> Unit) -> Int get() = { block ->
                val action: H.() -> Unit = { println(seed) }
                action()
                42
            }
            fun main() { println(H(8).apply {}) }
            """
            expectedOutput = "8\n42\n"
        default:
            source = """
            class H(val seed: Int)
            class Scope { private val apply: H.(H.() -> Unit) -> Int = { 42 } }
            fun main() { with(Scope()) { println(H(8).apply {}.seed) } }
            """
            expectedOutput = "8\n"
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try source.write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "ContextPriority", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), stdlibLibraryPath: try testStdlibArtifactPath()
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == expectedOutput)
    }

    @Test(arguments: [false, true], [0, 2])
    func scopePriorityMatchesJVM(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try fixture().write(toFile: input, atomically: true, encoding: .utf8)
        let options = CompilerOptions(
            moduleName: "ScopePriority", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == expected)
    }

    @Test(arguments: [0, 2])
    func importedLibraryPriorityMatchesJVM(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let source = try fixture()
        let main = try #require(source.range(of: "fun main() {"))
        let api = directory.appendingPathComponent("api.kt").path
        let library = directory.appendingPathComponent("Api").path
        try ("package callbacks\n" + source[..<main.lowerBound]).write(toFile: api, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "ScopeAPI", inputs: [api], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try ("import callbacks.*\n" + source[main.lowerBound...]).write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "ScopeConsumer", inputs: [input], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == expected)
    }

    @Test(arguments: ["explicit", "alias", "wildcard", "explicitFunction", "aliasFunction", "sameTierFunction", "missing"])
    func importTiersStayDistinct(_ mode: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let api = directory.appendingPathComponent("api.kt").path
        let library = directory.appendingPathComponent("Api").path
        try """
        package callbacks
        class Holder(val seed: Int)
        val Holder.apply: ((Int) -> Int) -> Int get() = { transform -> transform(seed) }
        """.write(toFile: api, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "ImportsAPI", inputs: [api], outputPath: library, emit: .library,
            target: defaultTargetTriple(), stdlibLibraryPath: stdlib
        )))
        let imports: String = switch mode {
        case "explicit": "import callbacks.Holder\nimport callbacks.apply\n"
        case "alias": "import callbacks.Holder\nimport callbacks.apply as operation\n"
        case "wildcard": "import callbacks.*\n"
        case "explicitFunction": "import callbacks.*\nimport kotlin.apply\n"
        case "aliasFunction": "import callbacks.*\nimport kotlin.also as apply\n"
        case "sameTierFunction": "import callbacks.Holder\nimport callbacks.apply\nimport kotlin.apply\n"
        default: "import callbacks.Holder\n"
        }
        let call: String
        let expectedOutput: String
        if mode == "aliasFunction" {
            call = "println(Holder(8).apply { println(it.seed) }.seed)"
            expectedOutput = "8\n8\n"
        } else {
            let name = mode == "alias" ? "operation" : "apply"
            call = "println(Holder(8).\(name) { it * 2 })"
            expectedOutput = "16\n"
        }
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try (imports + "fun main() { \(call) }").write(toFile: input, atomically: true, encoding: .utf8)
        let result = makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "ImportsConsumer", inputs: [input], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), stdlibLibraryPath: stdlib
        ))
        if ["explicitFunction", "sameTierFunction", "missing"].contains(mode) {
            #expect(result.exitCode != 0)
            #expect(result.diagnostics.contains { $0.severity == .error && $0.message.contains("it") })
        } else {
            try assertCompilationSucceeded(result)
            let execution = try CommandRunner.run(executable: output, arguments: [])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == expectedOutput)
        }
    }

    @Test(arguments: [false, true], ["explicit", "alias", "explicitFoo", "aliasFoo"])
    func explicitGetterPrecedesSamePackageGetter(fromLibrary: Bool, mode: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let model = directory.appendingPathComponent("model.kt").path
        let other = directory.appendingPathComponent("other.kt").path
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        let library = directory.appendingPathComponent("Api").path
        let callee = mode.hasSuffix("Foo") ? "foo" : "apply"
        let importedName = mode.hasPrefix("alias") ? "operation" : callee
        let alias = mode.hasPrefix("alias") ? " as \(callee)" : ""
        try "package model\nclass Holder(val seed: Int)".write(toFile: model, atomically: true, encoding: .utf8)
        try """
        package other
        import model.Holder
        val Holder.\(importedName): (Holder.() -> Unit) -> Int get() = { 1 }
        """.write(toFile: other, atomically: true, encoding: .utf8)
        try """
        package current
        import model.Holder
        import other.\(importedName)\(alias)
        val Holder.\(callee): (Holder.() -> Unit) -> Int get() = { 2 }
        fun main() { println(Holder(8).\(callee) { }) }
        """.write(toFile: input, atomically: true, encoding: .utf8)
        if fromLibrary {
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "PriorityAPI", inputs: [model, other], outputPath: library, emit: .library,
                target: defaultTargetTriple(), stdlibLibraryPath: stdlib
            )))
        }
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "PriorityConsumer", inputs: fromLibrary ? [input] : [model, other, input],
            outputPath: output, emit: .executable, searchPaths: fromLibrary ? [library + ".kklib"] : [],
            target: defaultTargetTriple(), stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "1\n")
    }
}

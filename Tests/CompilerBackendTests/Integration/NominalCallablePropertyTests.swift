import Foundation
@testable import CompilerBackend
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct NominalCallablePropertyTests {
    private let expected = "12\ngetters:1\n13\n14\nsum:15\n24\n26\n13\n6\n7\n22\n32\ngeneric\nnull\ngetters:4\n8\ngetters:5\n3\nreceiver\ngetter\nargument\n12\n16\n19\n8\n42\n9\n42\nthrowing-getter\ngetter\nthrowing-argument\nargument\ngetters:6\ninvoke\n12\n"
    private func fixture() throws -> String {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repository.appendingPathComponent("Scripts/diff_cases/nominal_callable_property_invocation.kt"), encoding: .utf8)
    }

    @Test(arguments: [false, true], [0, 2])
    func nominalPropertyInvocationMatchesJVM(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try fixture().write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "NominalCallbacks", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(), allowDefaultStdlibLibrary: !fromSource
        )))
        let execution = try CommandRunner.run(executable: output, arguments: [])
        #expect(execution.exitCode == 0, "\(execution.stderr)")
        #expect(execution.stdout == expected)
    }

    @Test(arguments: [0, 2])
    func importedLibraryRetainsPropertyAndInvokeTypes(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let source = try fixture()
        let main = try #require(source.range(of: "fun main() {"))
        let api = directory.appendingPathComponent("api.kt").path
        let library = directory.appendingPathComponent("Api").path
        let level = try #require(OptimizationLevel(rawValue: optimization))
        try ("package callbacks\n" + source[..<main.lowerBound]).write(toFile: api, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "NominalAPI", inputs: [api], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try ("import callbacks.*\n" + source[main.lowerBound...]).write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "NominalConsumer", inputs: [input], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let execution = try CommandRunner.run(executable: output, arguments: [])
        #expect(execution.exitCode == 0, "\(execution.stderr)")
        #expect(execution.stdout == expected)
    }

    @Test(arguments: ["generic", "singleton", "sentinel", "narrowLiteral", "classExtension", "interfaceExtension"])
    func operatorContractsRemainIntact(_ mode: String) throws {
        let source: String
        let outputExpected: String
        switch mode {
        case "generic":
            source = """
            class H
            class Action { operator fun <T> invoke(value: T): T = value }
            val H.callback: Action get() = Action()
            fun main() { println(H().callback<String>("typed")) }
            """
            outputExpected = "typed\n"
        case "singleton":
            source = """
            class H
            object Action {
                init { println("init") }
                val base = 10
                operator fun invoke(x: Int): Int = base + x
            }
            val H.callback: Action get() { println("getter"); return Action }
            fun main() { println(H().callback(1)); println(H().callback(2)) }
            """
            outputExpected = "getter\ninit\n11\ngetter\n12\n"
        case "sentinel":
            source = """
            class H
            class Action { operator fun invoke(): Long = Long.MIN_VALUE }
            val H.callback: Action get() = Action()
            fun main() {
                val absent: H? = null
                val present: H? = H()
                println(absent?.callback())
                println(present?.callback())
            }
            """
            outputExpected = "null\n-9223372036854775808\n"
        case "narrowLiteral":
            source = """
            class Action { operator fun invoke(x: Byte): Int = 1; operator fun invoke(x: String): Int = 2 }
            class H(val callback: Action)
            fun main() { println(H(Action()).callback(1)) }
            """
            outputExpected = "1\n"
        default:
            let provider = mode == "classExtension"
                ? "open class Provider { open val H.callback: Action get() = Action(seed) }"
                : "interface Provider { val H.callback: Action }"
            source = """
            class H(val seed: Int)
            open class Action(val base: Int) { open operator fun invoke(x: Int): Int = base + x }
            class DoubleAction(base: Int): Action(base) { override operator fun invoke(x: Int): Int = (base + x) * 2 }
            \(provider)
            class Impl: Provider\(mode == "classExtension" ? "()" : "") {
                override val H.callback: Action get() = DoubleAction(seed + 1)
            }
            fun main() { val provider: Provider = Impl(); with(provider) { println(H(8).callback(2)) } }
            """
            outputExpected = "22\n"
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try source.write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "OperatorContracts", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), stdlibLibraryPath: try testStdlibArtifactPath()
        )))
        let execution = try CommandRunner.run(executable: output, arguments: [])
        #expect(execution.exitCode == 0, "\(execution.stderr)")
        #expect(execution.stdout == outputExpected)
    }

    @Test(arguments: ["notOperator", "nullable", "privateInvoke", "privateMemberInvoke", "ambiguousLambdaReturn", "ambiguousNumericOverload", "privateGetter", "wrongArgument", "wrongArity", "unknownName", "spread", "typeArguments", "missingImport"])
    func invalidPropertyInvocationsStayRejected(_ mode: String) throws {
        let api = "/virtual/api.kt"
        let input = "/virtual/consumer.kt"
        let action: String = switch mode {
        case "notOperator": "class Action { fun invoke(x: Int): Int = x }"
        case "privateInvoke", "privateMemberInvoke": "class Action { private operator fun invoke(x: Int): Int = x }"
        case "ambiguousLambdaReturn": """
        class Action {
            @kotlin.jvm.JvmName("invokeInt") operator fun invoke(block: () -> Int): Int = 1
            @kotlin.jvm.JvmName("invokeString") operator fun invoke(block: () -> String): Int = 2
        }
        """
        case "ambiguousNumericOverload": "class Action { operator fun invoke(x: Byte): Int = 1; operator fun invoke(x: Long): Int = 2 }"
        default: "class Action { operator fun invoke(x: Int): Int = x }"
        }
        let isMember = ["privateMemberInvoke", "ambiguousLambdaReturn", "ambiguousNumericOverload"].contains(mode)
        let declaration = isMember ? "" : mode == "nullable" ? "val H.callback: Action? get() = null"
            : "\(mode == "privateGetter" ? "private " : "")val H.callback: Action get() = Action()"
        let call: String = switch mode {
        case "privateMemberInvoke": "H(Action()).callback(1)"
        case "ambiguousLambdaReturn": "H(Action()).callback { 42 }"
        case "ambiguousNumericOverload": "H(Action()).callback(1)"
        case "wrongArgument": "H().callback(\"bad\")"
        case "wrongArity": "H().callback(1, 2)"
        case "unknownName": "H().callback(unknown = 1)"
        case "spread": "H().callback(*intArrayOf(1))"
        case "typeArguments": "H().callback<String>(1)"
        default: "H().callback(1)"
        }
        let imports = mode == "missingImport" ? "import callbacks.H" : "import callbacks.*"
        let owner = isMember ? "class H(val callback: Action)" : "class H"
        let context = CompilerDriver().runFrontend(options: CompilerOptions(
            moduleName: "InvalidNominal", inputs: [api, input], outputPath: "/tmp/invalid-nominal", emit: .executable,
            target: defaultTargetTriple(), stdlibLibraryPath: try testStdlibArtifactPath()
        ), inMemorySources: [
            api: Data(("package callbacks\n" + owner + "\n" + action + "\n" + declaration).utf8),
            input: Data((imports + "\nfun main() { println(\(call)) }").utf8)
        ]).context
        #expect(context.diagnostics.hasError, "\(mode): \(context.diagnostics.diagnostics)")
        if ["ambiguousLambdaReturn", "ambiguousNumericOverload"].contains(mode) {
            #expect(context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0003" })
        }
    }
}

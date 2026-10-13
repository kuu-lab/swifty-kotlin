import Foundation
@testable import CompilerBackend
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct GenericExtensionPropertyInvocationTests {
    private let expected = "typed\n8\n2\nnominal\n8\n42\necho\n9\ntyped\ntyped\nchanged\nchanged\nidentity\nprefix\nchanged\nnull\nreads:3\nchanged\nreads:4\nchanged\ndirect\nbound\ntrue\nfalse\ntrue\nfalse\ntrue\ntrue\nfalse\ntrue\ntrue\nfalse\ncaptured\n"
    private func fixture() throws -> String {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repository.appendingPathComponent("Scripts/diff_cases/generic_extension_property_invocation.kt"), encoding: .utf8)
    }

    @Test(arguments: [false, true], [0, 2])
    func genericPropertiesMatchJVM(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try fixture().write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "GenericCallbacks", inputs: [input], outputPath: output, emit: .executable,
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
        try ("package callbacks\n" + source[..<main.lowerBound] + "\nval <reified T> T.accessorKind: (Any) -> Boolean\n    inline get() = { it is T }\n").write(toFile: api, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "GenericAPI", inputs: [api], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        let consumer = String(source[main.lowerBound...]).replacingOccurrences(of: "fun main() {", with: "fun matrixMain() {")
        try ("import callbacks.*\n" + consumer + "\nfun main() { matrixMain(); println(1.accessorKind(1)); println(1.accessorKind(\"x\")) }\n").write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "GenericConsumer", inputs: [input], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let execution = try CommandRunner.run(executable: output, arguments: [])
        #expect(execution.exitCode == 0, "\(execution.stderr)")
        #expect(execution.stdout == expected + "true\nfalse\n")
        let invalidConsumers = [
            "fun main() { println(Box<String?>(null).bounded) }",
            "fun main() { println(Box(\"text\").callback(1)) }",
            "fun main() { val box = Box(\"text\"); box.entry = 1 }",
            "fun main() { with(BoundedProvider<String>()) { println(Box(1).boundRead()) } }",
            "fun <U> erased(u: U): Boolean = u.kind(1)\nfun main() { println(erased(1)) }",
        ]
        for (index, invalid) in invalidConsumers.enumerated() {
            let badInput = directory.appendingPathComponent("invalid\(index).kt").path
            try ("import callbacks.*\n" + invalid).write(toFile: badInput, atomically: true, encoding: .utf8)
            let result = makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "InvalidGenericConsumer", inputs: [badInput],
                outputPath: directory.appendingPathComponent("invalid\(index)").path, emit: .executable,
                searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
            ))
            #expect(result.exitCode != 0, "Imported invalid consumer \(index) must be rejected")
            #expect(result.diagnostics.contains { $0.severity == .error })
        }
    }

    @Test(arguments: ["nullable", "owner", "object", "range", "reified", "accessorInline", "reifiedDNN", "reifiedNothing"], [0, 2])
    func receiverAndDeclarationBoundaries(_ mode: String, optimization: Int) throws {
        let source: String
        let expected: String
        switch mode {
        case "nullable":
            source = """
            val <T> T.accept: (T) -> String get() = { "property" }
            fun main() { val x: String? = null; println(x.accept(null)) }
            """
            expected = "property\n"
        case "owner":
            source = """
            class Box<T>(val value: T)
            class Token<X>(val value: X)
            class P<S>(val s: S) {
                val <T> Box<T>.accept: (Token<S>) -> String get() = { "property" }
                fun use(b: Box<Int>): String = b.accept(Token(s))
            }
            fun main() { println(P("ok").use(Box(1))) }
            """
            expected = "property\n"
        case "object":
            source = """
            class Box<T>(val value: T)
            fun main() { val p = object {
                val <T> Box<T>.read: () -> T get() = { value }
                fun use(b: Box<String>): String = b.read()
            }; println(p.use(Box("ok"))) }
            """
            expected = "ok\n"
        case "range":
            source = """
            val <T : Comparable<T>> ClosedRange<T>.accept: (T) -> String get() = { "ok" }
            fun main() { println((1..3).accept(2)) }
            """
            expected = "ok\n"
        case "reified":
            source = """
            inline val <reified T> T.kind: (Any) -> Boolean get() = { it is T }
            fun main() { println(1.kind(1)); println(1.kind("x")) }
            """
            expected = "true\nfalse\n"
        case "accessorInline":
            source = """
            val <reified T> T.kind: (Any) -> Boolean
                inline get() = { it is T }
            fun main() { println(1.kind(1)); println(1.kind("x")) }
            """
            expected = "true\nfalse\n"
        case "reifiedDNN":
            source = """
            inline val <reified T> T.kind: (Any?) -> Boolean get() = { it is T }
            fun <U> erased(u: U & Any): Boolean = u.kind(1)
            inline fun <reified U> typed(u: U & Any): (Any?) -> Boolean = { u.kind(it) }
            fun main() {
                println(erased("x")); println(erased(1))
                val p = typed<String?>("x")
                println(p(null)); println(p("x")); println(p(1))
            }
            """
            expected = "true\ntrue\ntrue\ntrue\nfalse\n"
        case "reifiedNothing":
            source = """
            inline val <reified T> T.kind: (Any?) -> Boolean get() = { it is T }
            fun main() { println(null.kind(null)); println(null.kind(1)); println(null.kind("x")) }
            """
            expected = "true\nfalse\nfalse\n"
        default: Issue.record("Unknown boundary"); return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try source.write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "GenericBoundary", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: try testStdlibArtifactPath()
        )))
        let execution = try CommandRunner.run(executable: output, arguments: [])
        #expect(execution.exitCode == 0, "\(execution.stderr)")
        #expect(execution.stdout == expected)
    }
}

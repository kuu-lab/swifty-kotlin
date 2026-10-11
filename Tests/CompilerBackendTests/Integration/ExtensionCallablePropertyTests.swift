@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct ExtensionCallablePropertyTests {
    private let expected = "7\n8\ngetters:2\n9\nreceiver;getter;arg;\n11\n16\n16\ntyped\n42\n20\n99\n7\n22\n22\nnull\nabsent:\n10\n8\n"
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
    private func fixture() throws -> String {
        try String(contentsOf: repository.appendingPathComponent("Scripts/diff_cases/extension_property_callback_invocation.kt"), encoding: .utf8)
    }

    @Test(arguments: [false, true], [0, 2])
    func directInvocationMatchesJVM(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try fixture().write(toFile: input, atomically: true, encoding: .utf8)
        let options = CompilerOptions(
            moduleName: "ExtensionCallable", inputs: [input], outputPath: output, emit: .executable,
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
    func importedGettersAndGenericFunctionTypesSurviveLibraryRoundTrip(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let level = try #require(OptimizationLevel(rawValue: optimization))
        func compile(_ source: String, module: String, emit: EmitMode, libraries: [String] = []) throws -> String {
            let input = directory.appendingPathComponent(module + ".kt").path
            let output = directory.appendingPathComponent(module).path
            try source.write(toFile: input, atomically: true, encoding: .utf8)
            let options = CompilerOptions(moduleName: module, inputs: [input], outputPath: output,
                                          emit: emit, searchPaths: libraries, target: defaultTargetTriple(),
                                          optLevel: level, stdlibLibraryPath: stdlib)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: module)
            return emit == .library ? output + ".kklib" : output
        }
        let source = try fixture()
        let main = try #require(source.range(of: "fun main() {"))
        let producer = "package callbacks\n" + source[..<main.lowerBound]
        let library = try compile(producer, module: "Callbacks", emit: .library)
        let consumer = "import callbacks.*\n" + source[main.lowerBound...]
        let output = try compile(consumer, module: "Consumer", emit: .executable, libraries: [library])
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == expected)
    }

    @Test(arguments: [false, true], [0, 2])
    func lexicalPriorityAndConcreteGenericOwner(fromLibrary: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let api = directory.appendingPathComponent("api.kt").path
        let library = directory.appendingPathComponent("Api").path
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try """
        package callbacks
        open class Box<T>(val value: T) {
            val String.read: () -> T get() = { value }
        }
        val Int.callback: () -> Int get() = { 10 }
        """.write(toFile: api, atomically: true, encoding: .utf8)
        try """
        import callbacks.*
        class TextBox: Box<String>("typed") {
            fun use(): String = "".read()
        }
        fun main() {
            val callback: Int.() -> Int = { 20 }
            println(1.callback())
            println(TextBox().use())
        }
        """.write(toFile: input, atomically: true, encoding: .utf8)
        if fromLibrary {
            let producer = CompilerOptions(moduleName: "Api", inputs: [api], outputPath: library,
                                           emit: .library, target: defaultTargetTriple(), optLevel: level,
                                           stdlibLibraryPath: stdlib)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: producer))
        }
        let consumer = CompilerOptions(moduleName: "Consumer", inputs: fromLibrary ? [input] : [api, input],
                                       outputPath: output, emit: .executable,
                                       searchPaths: fromLibrary ? [library + ".kklib"] : [],
                                       target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: consumer))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "20\ntyped\n")
    }

    @Test(arguments: ["explicit", "alias", "missing"])
    func libraryImportsControlGetterVisibility(_ mode: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let api = directory.appendingPathComponent("api.kt").path
        let libraryOutput = directory.appendingPathComponent("Api").path
        try "package callbacks\nclass Holder\nval Holder.callback: (Int) -> Int get() = { it }\n"
            .write(toFile: api, atomically: true, encoding: .utf8)
        let producer = CompilerOptions(moduleName: "Api", inputs: [api], outputPath: libraryOutput,
                                       emit: .library, target: defaultTargetTriple(), stdlibLibraryPath: stdlib)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: producer))
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        let imports = switch mode {
        case "explicit": "import callbacks.callback\n"
        case "alias": "import callbacks.callback as renamed\n"
        default: ""
        }
        let name = mode == "alias" ? "renamed" : "callback"
        let source = "import callbacks.Holder\n" + imports + "fun main() { println(Holder().\(name)(7)) }\n"
        try source.write(toFile: input, atomically: true, encoding: .utf8)
        let consumer = CompilerOptions(moduleName: "Consumer", inputs: [input], outputPath: output,
                                       emit: .executable, searchPaths: [libraryOutput + ".kklib"],
                                       target: defaultTargetTriple(), stdlibLibraryPath: stdlib)
        if mode == "missing" {
            let context = CompilerDriver().runFrontend(options: consumer).context
            #expect(context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
        } else {
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: consumer))
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "7\n")
        }
    }

    @Test(arguments: ["nullable", "wrongArgument", "namedArgument", "typeArguments", "missingReceiver", "nonCallable", "private", "missingImport", "super", "lexicalRead"])
    func invalidInvocationsStayRejected(_ kind: String) throws {
        let api = "/tmp/callback-api-\(UUID().uuidString).kt"
        let caller = "/tmp/callback-caller-\(UUID().uuidString).kt"
        var declaration = "class Holder\nval Holder.callback: (Int) -> Int get() = { it }\n"
        let call: String
        switch kind {
        case "nullable":
            declaration = "class Holder\nval Holder.callback: (() -> Int)? get() = null\n"
            call = "Holder().callback()"
        case "wrongArgument": call = "Holder().callback(\"bad\")"
        case "namedArgument": call = "Holder().callback(value = 7)"
        case "typeArguments": call = "Holder().callback<Int>(7)"
        case "missingReceiver":
            declaration = "class Holder\nval Holder.callback: String.() -> Int get() = { length }\n"
            call = "Holder().callback()"
        case "nonCallable":
            declaration = "class Holder\nval Holder.callback: Int get() = 7\n"
            call = "Holder().callback()"
        case "missingImport": call = "Holder().callback(7)"
        case "lexicalRead":
            declaration = "class Holder\n"
            call = "1.callback"
        case "super":
            declaration = "open class Holder\nval Holder.callback: () -> Int get() = { 7 }\n"
            call = "Child().run()"
        default:
            declaration = "class Holder\nprivate val Holder.callback: () -> Int get() = { 7 }\n"
            call = "Holder().callback()"
        }
        let options = CompilerOptions(moduleName: "InvalidCallback", inputs: [api, caller], outputPath: "/tmp/invalid-callback",
                                      emit: .executable, target: defaultTargetTriple(), stdlibLibraryPath: try testStdlibArtifactPath())
        let imports = kind == "missingImport" ? "import callbacks.Holder\n" : "import callbacks.*\n"
        let extra = kind == "super" ? "class Child: Holder() { fun run(): Int = super.callback() }\n" : ""
        let setup = kind == "lexicalRead" ? "val callback: Int.() -> Int = { 20 }; " : ""
        let context = CompilerDriver().runFrontend(options: options, inMemorySources: [
            api: Data(("package callbacks\n" + declaration).utf8),
            caller: Data((imports + extra + "fun main() { \(setup)println(\(call)) }\n").utf8)
        ]).context
        #expect(context.diagnostics.hasError, "\(kind): \(context.diagnostics.diagnostics)")
        if kind == "private" {
            #expect(context.diagnostics.diagnostics.contains { $0.message.contains("private") })
        }
    }
}

@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct ReceiverLambdaMemberExtensionExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func parserMemberExtensionMatchesJVM(fromSource: Bool, optimization: Int) throws {
        let source = try diffCaseSource("receiver_lambda_member_extension_parse.kt")
        try assertOutput(source, expected: "3\n", fromSource: fromSource, optimization: optimization)
    }

    @Test(arguments: [false, true], [0, 2])
    func dispatchStateAndSeparatorEffectsArePreserved(fromSource: Bool, optimization: Int) throws {
        try assertOutput("""
        fun interface Parser<out T> { fun parse(source: String): T }
        class State(var source: String) {
            fun <T> Parser<T>.parse(): T {
                val result = parse(source)
                source = source + "b"
                return result
            }
        }
        fun <T> parser(block: State.() -> T): Parser<T> = Parser { source -> block(State(source)) }
        fun <T> combine(element: Parser<T>, separator: Parser<Unit>): Parser<T> = parser {
            separator.parse()
            element.parse()
        }
        fun main() {
            val element: Parser<Int> = Parser { source -> source.length }
            val separator: Parser<Unit> = Parser { source -> println(source) }
            println(combine(element, separator).parse("a"))
            println(element.parse("direct"))
        }
        """, expected: "a\n2\n6\n", fromSource: fromSource, optimization: optimization)
    }

    @Test
    func memberExtensionGetAndSetDispatchInsideAnonymousObject() throws {
        try assertOutput("""
        fun <T, R> myWith(receiver: T, block: T.() -> R): R = receiver.block()
        object Foo2 { operator fun Any?.get(key: String) = "OK" }
        object Main {
            fun bar() = myWith(Foo2) {
                val x = object { val y = 38["Hello!"] }
                x.y
            }
        }
        fun main() { println(Main.bar()) }
        """, expected: "OK\n", fromSource: false, optimization: 0)

        try assertOutput("""
        var result = "fail"
        fun <T, R> myWith(receiver: T, block: T.() -> R): R = receiver.block()
        object Foo2 {
            operator fun Any?.get(key: String) = "OK"
            operator fun Any?.set(key: String, value: String) { result = value }
        }
        object Main {
            fun bar() = myWith(Foo2) {
                val x = object { init { 38["Hello!"] = "OK" } }
                result
            }
        }
        fun main() { println(Main.bar()) }
        """, expected: "OK\n", fromSource: false, optimization: 0)
    }

    private func assertOutput(_ source: String, expected: String, fromSource: Bool, optimization: Int) throws {
        try withTemporaryFile(contents: source) { path in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }
            let options = CompilerOptions(
                moduleName: "ReceiverLambdaMemberExtension", inputs: [path], outputPath: output,
                emit: .executable, target: defaultTargetTriple(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
                allowDefaultStdlibLibrary: !fromSource
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == expected)
            #expect(result.stderr.isEmpty)
        }
    }
}

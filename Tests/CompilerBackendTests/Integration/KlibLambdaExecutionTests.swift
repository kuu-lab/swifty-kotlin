@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct KlibLambdaExecutionTests {
    @Test(arguments: [0, 2])
    func executesSourceAndLatestNativeKlibLambdas(optimization: Int) throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("CompilerCoreTests/Klib/Fixtures/Kotlin2_4_21/Lambdas")
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let source = directory.appendingPathComponent("main.kt")
        try """
        import kliblambdas.*

        fun main() {
            val increment = make()
            println(increment(5))
            println(capture(10)(7))
            println(twoCaptures(4, 9)())
            val first = counter(10)
            val second = counter(100)
            println(first())
            println(first())
            println(second())
            println(invokeInside(30))
            val outer = nested(8)
            val inner = outer(4)
            println(inner())
            println(outer(9)())
            val shared = sharedState()
            println(shared())
            println(shared())
            println(shared())
            println(mutateAfterCapture())
            println(Holder(40).capture()(2))
            println(text("pre-")("fix"))
            println(keep(77)())
            println(keep("generic")())
            val erased: Any = keep(88)()
            println(erased is Int)
            println(binary(10)(3, 4))
            println(apply({ it * 3 }, 7))
            var outside = 10
            println(apply({ outside += it; outside }, 2))
            println(outside)
            try {
                apply({ throw IllegalStateException("expected") }, 1)
            } catch (failure: IllegalStateException) {
                println("caught")
            }
        }
        """.write(to: source, atomically: true, encoding: .utf8)
        let expected = """
        6
        17
        13
        11
        12
        101
        32
        12
        17
        1
        2
        3
        9
        42
        pre-fix
        77
        generic
        true
        17
        21
        12
        12
        caught

        """
        for useKlib in [false, true] {
            let mode = useKlib ? "klib" : "source"
            let output = directory.appendingPathComponent(mode).path
            let result = makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "KlibLambdas_\(mode)",
                inputs: useKlib ? [source.path] : [fixture.appendingPathComponent("Lambdas.kt").path, source.path],
                outputPath: output, emit: .executable,
                searchPaths: useKlib ? [fixture.appendingPathComponent("lambdas.klib").path] : [],
                target: defaultTargetTriple(), optLevel: optimization == 0 ? .O0 : .O2
            ))
            try assertCompilationSucceeded(result, context: "KUU-2692 \(mode) O\(optimization)")
            let unsupported = result.diagnostics.filter {
                ["KSWIFTK-LIB-0003", "KSWIFTK-LIB-0004", "KSWIFTK-LIB-0027", "KSWIFTK-LIB-0028", "KSWIFTK-LIB-0029"].contains($0.code)
            }
            try #require(unsupported.isEmpty, "\(mode) O\(optimization): \(unsupported.map { $0.code + ": " + $0.message }.joined(separator: ", "))")
            let run = try CommandRunner.run(executable: output, arguments: [], timeout: 30)
            #expect(run.exitCode == 0, "\(mode): \(run.stderr)")
            #expect(run.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected, "\(mode) O\(optimization)")
        }
    }
}

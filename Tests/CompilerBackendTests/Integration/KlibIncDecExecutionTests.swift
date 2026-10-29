@testable import CompilerCore
import Foundation
import Testing

/// Serialized `v++` / `v--` reach KlibBodyLowerer as `inc()` / `dec()`
/// intrinsics. Byte/Short/UByte/UShort keep the operand type, so the 64-bit
/// slot must wrap back to that width, and Float/Double slots hold IEEE bit
/// patterns that need the floating-point add/sub.
@Suite
struct KlibIncDecExecutionTests {
    @Test(arguments: [0, 2])
    func executesSourceAndLatestNativeKlibIncrementDecrement(optimization: Int) throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("CompilerCoreTests/Klib/Fixtures/Kotlin2_4_21/IncDec")
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let source = directory.appendingPathComponent("main.kt")
        try """
        import klibincdec.*

        fun main() {
            println(byteInc(127))
            println(byteDec(-128))
            println(byteInc(5))
            println(shortInc(32767))
            println(shortDec(-32768))
            println(ubyteInc(255u))
            println(ubyteDec(0u))
            println(ushortInc(65535u))
            println(ushortDec(0u))
            println(charInc('\\uFFFF').code)
            println(intInc(Int.MAX_VALUE))
            println(doubleInc(1.5))
            println(doubleDec(-0.5))
            println(floatInc(2.25f))
            println(floatDec(0.5f))
        }
        """.write(to: source, atomically: true, encoding: .utf8)
        // Checked against Kotlin/JVM 2.4.21 with IncDec.kt as source.
        let expected = """
        -128
        127
        6
        -32768
        32767
        0
        255
        0
        65535
        0
        -2147483648
        2.5
        -1.5
        3.25
        -0.5

        """
        for useKlib in [false, true] {
            let mode = useKlib ? "klib" : "source"
            let output = directory.appendingPathComponent(mode).path
            let result = makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "KlibIncDec_\(mode)",
                inputs: useKlib ? [source.path] : [fixture.appendingPathComponent("IncDec.kt").path, source.path],
                outputPath: output, emit: .executable,
                searchPaths: useKlib ? [fixture.appendingPathComponent("incdec.klib").path] : [],
                target: defaultTargetTriple(), optLevel: optimization == 0 ? .O0 : .O2
            ))
            try assertCompilationSucceeded(result, context: "klib inc/dec \(mode) O\(optimization)")
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

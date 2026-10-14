#if os(macOS)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import TestStdlibCache
import Testing

@Suite(.serialized)
struct IOApplePointerElementExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func bytePointerReadsValuesWithExplicitImports(library: Bool, optimization: Int) throws {
        if library { TestStdlibCache.shared.prepare() }
        let artifact = library ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: directory) }
        let source = directory.appendingPathComponent("main.kt")
        try """
        @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.addressOf
        import kotlinx.cinterop.get
        import kotlinx.cinterop.usePinned
        fun first(pointer: CPointer<ByteVar>): Byte = pointer[0]
        fun ByteArray.implicitFirst(): Byte = usePinned { it.addressOf(0)[0] }
        fun ByteArray.innerFirst(): Byte = with(byteArrayOf(7)) { usePinned { it.addressOf(0)[0] } }
        fun ByteArray.shadowed(): Int {
            fun usePinned(block: () -> Int): Int = block() + 100
            return usePinned { 7 }
        }
        fun main() {
            val bytes = byteArrayOf(-1, 0, 65)
            println(bytes.implicitFirst())
            println(bytes.innerFirst())
            println(bytes.shadowed())
            bytes.usePinned {
                val pointer = it.addressOf(0)
                val second: Byte = pointer.get(1)
                println(first(pointer))
                println(second)
                println(pointer[2])
            }
            println(bytes.isNotEmpty())
            println(byteArrayOf().isNotEmpty())
        }
        """.write(to: source, atomically: true, encoding: .utf8)
        let executable = directory.appendingPathComponent("main")
        let ctx = try runCodegenPipeline(
            inputPath: source.path, moduleName: "AppleBytePointerElements", outputPath: executable.path,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            allowDefaultStdlibLibrary: false, stdlibLibraryPath: artifact
        )
        try LinkPhase().run(ctx)
        let result = try CommandRunner.run(executable: executable.path, arguments: [])
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == "-1\n7\n107\n-1\n0\n65\ntrue\nfalse\n")
    }
}
#endif

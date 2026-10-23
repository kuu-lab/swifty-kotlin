@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-3064: typed ByteBuffer operations and byte order survive source and artifact compilation.
    @Test
    func testJavaNioByteBufferTypedAccessorsAcrossSourceAndFreshLibrary() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-bytebuffer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = """
        import java.nio.ByteBuffer
        import java.nio.ByteOrder

        fun main() {
            val relative = ByteBuffer.allocate(28)
            println(relative.order() == ByteOrder.BIG_ENDIAN)
            println(ByteOrder.nativeOrder() == ByteOrder.LITTLE_ENDIAN)
            relative.putChar('A')
                .putShort((-1234).toShort())
                .putInt(0x12345678)
                .putLong(0x0102030405060708L)
                .putFloat(1.5f)
                .putDouble(-2.25)
            println(relative.position())
            relative.flip()
            println(relative.getChar().code)
            println(relative.getShort())
            println(relative.getInt())
            println(relative.getLong())
            println(relative.getFloat())
            println(relative.getDouble())

            val little = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN)
            little.putInt(0x01020304)
            println(little.array().joinToString(","))
            little.flip()
            println(little.getInt())
            little.putInt(0, 0x0a0b0c0d)
            println(little.getInt(0))
            println(little.position())

            val ordered = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN)
            println(ordered.duplicate().order() == ByteOrder.BIG_ENDIAN)
            println(ordered.slice().order() == ByteOrder.BIG_ENDIAN)
            println(ordered.asReadOnlyBuffer().order() == ByteOrder.BIG_ENDIAN)

            val absolute = ByteBuffer.allocate(28)
            absolute.putChar(0, 'Z')
            absolute.putShort(2, (-2).toShort())
            absolute.putInt(4, 0x01020304)
            absolute.putLong(8, 0x0102030405060708L)
            absolute.putFloat(16, 3.25f)
            absolute.putDouble(20, -5.5)
            println(absolute.position())
            println(absolute.getChar(0).code)
            println(absolute.getShort(2))
            println(absolute.getInt(4))
            println(absolute.getLong(8))
            println(absolute.getFloat(16))
            println(absolute.getDouble(20))

            val copied = ByteBuffer.allocate(3).put(byteArrayOf(1, 2, 3)).flip()
            val destination = ByteArray(3)
            copied.get(destination)
            println(destination.joinToString(","))
        }
        """
        let input = directory.appendingPathComponent("Main.kt")
        try source.write(to: input, atomically: true, encoding: .utf8)

        let expected = """
        true
        true
        28
        65
        -1234
        305419896
        72623859790382856
        1.5
        -2.25
        4,3,2,1
        16909060
        168496141
        4
        true
        true
        true
        0
        90
        -2
        16909060
        72623859790382856
        3.25
        -5.5
        1,2,3
        """ + "\n"

        let artifactPath = try Self.buildStdlibArtifact()
        for (surface, library) in [("Source", nil as String?), ("Library", artifactPath)] {
            for optimization in [OptimizationLevel.O0, .O2] {
                let output = directory.appendingPathComponent("bytebuffer-\(surface)-\(optimization)").path
                let context = try runCodegenPipeline(
                    inputPath: input.path,
                    moduleName: "JavaNioByteBuffer\(surface)\(optimization)",
                    outputPath: output,
                    optLevel: optimization,
                    allowDefaultStdlibLibrary: false,
                    stdlibLibraryPath: library
                )
                try assertNoDiagnosticErrors(context)
                try LinkPhase().run(context)
                let result = try CommandRunner.run(
                    executable: output,
                    arguments: [],
                    currentDirectoryPath: directory.path
                )
                #expect(result.exitCode == 0, "\(surface) \(optimization): \(result.stderr)")
                #expect(result.stderr.isEmpty)
                #expect(result.stdout == expected, "\(surface) \(optimization)")
            }
        }
    }
}

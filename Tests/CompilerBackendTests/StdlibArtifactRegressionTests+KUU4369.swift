@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-4369: missing java.time values and typed java.nio buffers work through a fresh stdlib artifact.
    @Test
    func testJavaTimeAndNioGapTypesThroughFreshLibrary() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-kuu4369-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = """
        import java.nio.CharBuffer
        import java.nio.IntBuffer
        import java.nio.LongBuffer
        import java.time.Clock
        import java.time.ChronoUnit
        import java.time.LocalDate
        import java.time.MonthDay
        import java.time.Year
        import java.time.YearMonth
        import java.time.ZoneId
        import java.time.ZoneOffset
        import java.time.ZonedDateTime
        import java.time.format.DateTimeFormatter

        fun main() {
            val year = Year.of(2024)
            println(year.isLeap)
            println(YearMonth.of(2024, 2).atEndOfMonth())
            println(YearMonth.now().monthValue in 1..12)
            val monthDay = MonthDay.of(2, 29)
            println(monthDay)
            println(monthDay.atYear(2023))

            val zoned = ZonedDateTime.of(2024, 2, 29, 12, 0, 0, 0, ZoneId.of("UTC"))
            println(zoned.zone.id)
            println(ZonedDateTime.now(ZoneId.of("UTC")).zone.id)
            println(zoned.offset)
            println(ChronoUnit.DAYS.between(LocalDate.of(2024, 2, 29), LocalDate.of(2024, 3, 9)))
            println(DateTimeFormatter.BASIC_ISO_DATE.format(LocalDate.of(2024, 2, 29)))
            val clock = Clock.systemUTC()
            println(clock.zone == ZoneOffset.UTC)
            println(clock.instant().toEpochMilli() > 0)

            val chars = CharBuffer.allocate(3).put('A').put('B').flip()
            println(chars.toString())
            val ints = IntBuffer.allocate(2).put(8).put(9).flip()
            println(ints.get())
            println(ints.get())
            val longs = LongBuffer.allocate(3).put(10L).put(11L).put(12L).flip()
            println(longs.get())
            println(longs.get())
            println(longs.get())
        }
        """
        let input = directory.appendingPathComponent("Main.kt")
        try source.write(to: input, atomically: true, encoding: .utf8)

        let expected = """
        true
        2024-02-29
        true
        --02-29
        2023-02-28
        UTC
        UTC
        Z
        9
        20240229
        true
        true
        AB
        8
        9
        10
        11
        12
        """ + "\n"

        let artifactPath = try Self.buildStdlibArtifact()
        let output = directory.appendingPathComponent("kuu4369-library-O0").path
        let context = try runCodegenPipeline(
            inputPath: input.path,
            moduleName: "KUU4369LibraryO0",
            outputPath: output,
            optLevel: .O0,
            allowDefaultStdlibLibrary: false,
            stdlibLibraryPath: artifactPath,
            prepareTestStdlibCache: false
        )
        try assertNoDiagnosticErrors(context)
        try LinkPhase().run(context)
        let result = try CommandRunner.run(
            executable: output,
            arguments: [],
            currentDirectoryPath: directory.path
        )
        #expect(result.exitCode == 0, "Library O0: \(result.stderr)")
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == expected, "Fresh library O0")
    }
}

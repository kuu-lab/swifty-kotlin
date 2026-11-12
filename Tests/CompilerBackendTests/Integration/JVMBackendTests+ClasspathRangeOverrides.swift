#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedRangeKeepsConcreteEndpointProperties() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture
            data class Day(val number: Int) : Comparable<Day> {
                override fun compareTo(other: Day): Int = number.compareTo(other.number)
            }
            class Days(override val start: Day, override val endInclusive: Day) : ClosedRange<Day> {
                override fun contains(value: Day): Boolean = value >= start && value <= endInclusive
                override fun isEmpty(): Boolean = start > endInclusive
            }
            fun days(): Days = Days(Day(1), Day(3))
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.days
            fun main() {
                println(days().start.number)
                println(days().endInclusive.number)
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "1\n3\n")
        }
    }
}
#endif

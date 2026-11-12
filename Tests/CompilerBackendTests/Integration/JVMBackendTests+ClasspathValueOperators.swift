#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedValueClassArithmeticUsesPhysicalCarriers() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture

            @JvmInline
            value class Dimension(val value: Float) {
                operator fun plus(other: Dimension): Dimension = Dimension(value + other.value)
                operator fun times(other: Float): Dimension = Dimension(value * other)
                operator fun times(other: Int): Dimension = Dimension(value * other)
                operator fun div(other: Dimension): Float = value / other.value
            }
            fun dimension(value: Float): Dimension = Dimension(value)
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.dimension
            fun main() {
                val one = dimension(2.0f)
                val two = dimension(4.0f)
                println((one + two).value)
                println((one * 1.5f).value)
                println(two.times(3).value)
                println(two / one)
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "6.0\n3.0\n12.0\n2.0\n")
        }
    }
}
#endif

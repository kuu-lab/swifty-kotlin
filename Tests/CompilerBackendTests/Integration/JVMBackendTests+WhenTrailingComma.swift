#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func whenConditionListAcceptsTrailingComma() throws {
        try withWorkspace { root in
            let source = #"""
            enum class Direction { North, South, East, West }

            fun axis(direction: Direction): String = when (direction) {
                Direction.North,
                Direction.South,
                -> "vertical"
                Direction.East, Direction.West, -> "horizontal"
            }

            fun parity(value: Int): String = when {
                value % 2 == 0,
                -> "even"
                else -> "odd"
            }

            fun main() { println(axis(Direction.South) + " " + axis(Direction.West) + " " + parity(3)) }
            """#
            let runtime = try m11Runtime()
            let compiled = try compile(source, root: root, mode: .jvmJar, classpath: runtime.components(separatedBy: ":"))
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")
            let artifact = root.appendingPathComponent("hello.jar").path
            let run = try java(["-cp", artifact + ":" + runtime, "HelloKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "vertical horizontal odd\n")
        }
    }
}
#endif

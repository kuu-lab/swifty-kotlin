#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func indexedArrayOperatorsPreserveResolvedGetSetAndEvaluationOrder(mode: EmitMode) throws {
        let source = """
        data class Point(val x: Int, val y: Int)
        class Notification
        val data = arrayOf(charArrayOf('O'))
        operator fun Array<CharArray>.set(at: Point, c: Char) {
            print("S"); this[at.y][at.x] = c
        }
        operator inline fun Array<CharArray>.get(at: Point): Char {
            print("T"); return this[at.y][at.x]
        }
        operator fun Array<CharArray>.get(at: Notification) { print("U") }
        fun grid(): Array<CharArray> { print("G"); return data }
        fun point(): Point { print("P"); return Point(0, 0) }
        fun value(): Char { print("V"); return '.' }
        fun main() {
            grid()[point()] = value(); println(data[0][0])
            println(grid()[point()])
            grid().set(point(), value()); println(data[0][0])
            println(grid().get(point()))
            data[0][0] = '#'; println(data[0][0])
            val ints = intArrayOf(1); ints[0] = 7; println(ints[0])
            data[Notification()]; println(); data.get(Notification()); println()
        }
        """
        try withWorkspace { root in
            let library = try ownStdlibRuntime()
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == "GPVS.\nGPT.\nGPVS.\nGPT.\n#\n7\nU\nU\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif

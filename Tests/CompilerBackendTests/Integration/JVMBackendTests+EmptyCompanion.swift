#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func companionWithoutBodyEmitsDefaultAndNamedSingletons(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            data class Schedule(val count: Int) {
                companion object
            }

            class Room {
                companion object Factory
                fun number(): Int = 42
            }

            fun Schedule.Companion.empty(): Schedule = Schedule(0)
            fun Room.Factory.create(): Room = Room()

            fun main() {
                println(Schedule.empty().count)
                println(Room.create().number())
            }
            """, expected: "0\n42\n", mode: mode, root: root)
        }
    }
}
#endif

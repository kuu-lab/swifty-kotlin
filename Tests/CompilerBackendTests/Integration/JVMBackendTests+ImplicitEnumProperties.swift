#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func implicitEnumPropertiesUseEnumReceiverAndStaticEntries(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            interface Labeled { val label: String }

            enum class Room : Labeled {
                NORTH, SOUTH;

                override val label = "$name:$ordinal"

                fun local(name: String, ordinal: Int) = "$name:$ordinal"

                companion object {
                    fun first(): Room = entries[0]
                    fun size(): Int = entries.size
                }
            }

            fun main() {
                val north: Labeled = Room.first()
                println(north.label)
                println(Room.SOUTH.label)
                println(Room.SOUTH.local("local", 7))
                println(Room.size())
            }
            """, expected: "NORTH:0\nSOUTH:1\nlocal:7\n2\n", mode: mode, root: root)
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func iterableFirstOrNullPredicateStopsAtFirstMatch(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            enum class Room { NORTH, SOUTH }

            fun containsSouth(rooms: Iterable<Room>): Boolean {
                rooms.firstOrNull { if (it == Room.SOUTH) return true; false }
                return false
            }

            fun main() {
                println(Room.entries.firstOrNull { it.name == "SOUTH" })
                println(Room.entries.firstOrNull { it.name == "WEST" })
                val visited = mutableListOf<String?>()
                val rooms: Iterable<String?> = listOf(null, "north", "south")
                println(rooms.firstOrNull { visited.add(it); it != null })
                println(visited)
                println(emptyList<String>().firstOrNull { visited.add(it); true })
                println(visited)
                println(containsSouth(Room.entries))
            }
            """, expected: "SOUTH\nnull\nnorth\n[null, north]\nnull\n[null, north]\ntrue\n", mode: mode, root: root)
        }
    }
}
#endif

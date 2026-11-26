#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

/// A for-loop over a Map subtype always took Map.Entry<K, V> as its element
/// type, even when Sema selected a user-declared iterator() operator whose
/// next() returns something else. Only the stdlib Map iterator yields entries.
@Suite
struct MapUserIteratorLoopElementTypeTests {
    @Test
    func userIteratorOnMapSubtypeDecidesLoopElementType() throws {
        _ = try semaContext(from: """
            class Tags(private val backing: Map<String, Int>) : Map<String, Int> by backing {
                operator fun iterator(): Iterator<String> = backing.keys.iterator()
            }

            fun use(tags: Tags): Int {
                var total = 0
                for (tag in tags) {
                    val name: String = tag
                    total += name.length
                }
                return total
            }
            """)
    }

    @Test
    func stdlibMapIteratorStillYieldsEntries() throws {
        _ = try semaContext(from: """
            fun use(values: Map<String, Int>): Int {
                var total = 0
                for (entry in values) {
                    val key: String = entry.key
                    total += key.length + entry.value
                }
                for ((key, value) in values) total += key.length + value
                return total
            }
            """)
    }
}
#endif

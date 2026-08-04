@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesEnumEdgeCoverage() throws {
        let source = """
        enum class Direction {
            NORTH,
            SOUTH,
        }

        fun main() {
            println(Direction.entries)
            println(enumValues<Direction>().toList())
            println(enumValueOf<Direction>("NORTH"))
            println(Direction.SOUTH.name)
            println(Direction.SOUTH.ordinal)

            try {
                println(enumValueOf<Direction>("WEST"))
            } catch (e: Throwable) {
                println("invalid-enum-name")
            }
        }
        """

        // BUG-172 fix made `entries`/`enumValues<T>()` hold the real enum
        // singletons (matching what a literal `Direction.NORTH` reference
        // produces) instead of pre-formatted name strings, so identity/equality
        // and indexed access (`entries[0]`) are correct. Tradeoff: printing a
        // *collection* of raw enum values now shows the ordinal, not the name,
        // because enum values carry no runtime type tag outside the specific
        // call shapes EnumNameAccessLoweringPass rewrites at compile time — this
        // reproduces identically for `listOf(Direction.NORTH, Direction.SOUTH)`
        // with no entries/values involved. Tracked separately as BUG-173 (see
        // TODO.md); out of scope for BUG-172.
        try assertKotlinOutput(
            source,
            moduleName: "EnumEdgeCoverage",
            expected:
                """
                [0, 1]
                [0, 1]
                NORTH
                SOUTH
                1
                invalid-enum-name
                """
                + "\n"
        )
    }

    // BUG-172: `EnumEntries<T>` was registered as a completely empty synthetic
    // interface (`HeaderHelpers+SyntheticEnumStubs.swift`'s
    // `ensureEnumEntriesInterface`) with no `get` operator, so `entries[i]` /
    // `enumEntries<T>()[i]` found no member candidate in Sema and the KIR
    // indexed-access lowering (`CallLowerer+Operators.swift`) fell through to
    // its generic built-in array-access path, which unconditionally emits
    // `kk_array_get` — a `RuntimeArrayBox`-only intrinsic. `entries`'s actual
    // runtime representation is a `RuntimeListBox` (`kk_enum_make_entries_list`
    // in RuntimeEnum.swift), so this panicked with KSWIFTK-LINK-0003 at
    // runtime. `values()`/`enumValues<T>()` (`Array<T>`/`RuntimeArrayBox`) and
    // `for (d in entries)` (iterator-based, not indexed) were unaffected,
    // which is what made this a narrower bug than "EnumEntries is broken".
    //
    // Fixed by registering a `get(index: Int): T` operator on `EnumEntries<T>`
    // that reuses the same `__kk_list_get` bridge `List<E>.get` already uses.
    // That alone surfaced a second, previously-masked bug: `entries$get()` /
    // `enumValues<T>()` / `enumEntries<T>()` populated their backing array with
    // each entry's *name string* (so a crash-free `println(entries[0])` would
    // have "looked right" by coincidence) instead of the entry singleton
    // itself, so indexed access actually returned a `String` standing in for
    // the enum value — wrong identity/equality, and it would misbehave the
    // moment anything past printing touched it. Fixed by referencing the entry
    // singleton directly (`DataEnumSealedSynthesisPass+EnumSynthesis.swift`,
    // `CallLowerer+EnumStdlib.swift`), matching what a literal
    // `Direction.NORTH` reference already lowers to.
    func testCodegenEnumEntriesIndexedAccessReturnsRealSingleton() throws {
        let source = """
        enum class Direction { NORTH, SOUTH, EAST, WEST }

        fun main() {
            println(Direction.entries[0])
            println(Direction.entries[3])
            println(enumEntries<Direction>()[1])
            println(Direction.entries[0] == Direction.NORTH)
            println(Direction.entries[1] == Direction.SOUTH)
            println(Direction.entries[0] == Direction.SOUTH)
            println(enumValues<Direction>()[2] == Direction.EAST)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumEntriesIndexedAccess",
            expected:
                """
                NORTH
                WEST
                SOUTH
                true
                true
                false
                true
                """
                + "\n"
        )
    }
}


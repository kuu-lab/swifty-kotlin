#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendEnumEdgeCoverageTests {

    @Test
    func testEnumEntryBodyImplicitNameUsesCurrentEntry() throws {
        let source = """
        enum class E {
            A {
                override fun describe(): String = "base-" + name
            };
            abstract fun describe(): String
        }

        fun main() { println(E.A.describe()) }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumEntryBodyImplicitName",
            expected: "base-A\n"
        )
    }

    /// DEBT-DIFF-007: elements returned by `values()`/`entries` cross an
    /// Any-erased collection boundary as `RuntimeIntBox` handles, while the
    /// enum HOF lambda consumes a raw ordinal. The lambda entry point must
    /// unbox the callback argument before constructor-property access; without
    /// that normalization, `$enumConstructorProperty$...` receives a boxed
    /// pointer as its ordinal and falls through to `kk_abort_unreachable`.
    @Test
    func testCodegenEnumCollectionHOFUnboxesConstructorPropertyReceiver() throws {
        let source = """
        enum class Color(val rgb: Int) {
            RED(0xFF0000),
            GREEN(0x00FF00),
            BLUE(0x0000FF),
        }

        fun main() {
            println(Color.entries.find { it.rgb == 0xFF0000 })
            println(Color.values().find { it.rgb == 0x00FF00 })
            println(Color.entries.find { it.rgb == 123456 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumCollectionHOFConstructorProperty",
            expected:
                """
                RED
                GREEN
                null
                """
                + "\n"
        )
    }

    /// BUG-178: `EnumEntries<T>` was registered as a completely empty
    /// synthetic interface (`HeaderHelpers+SyntheticEnumStubs.swift`'s
    /// `ensureEnumEntriesInterface`) with no `get` operator, so `entries[i]` /
    /// `enumEntries<T>()[i]` found no member candidate in Sema and the KIR
    /// indexed-access lowering (`CallLowerer+Operators.swift`) fell through to
    /// its generic built-in array-access path, which unconditionally emits
    /// `kk_array_get` — a `RuntimeArrayBox`-only intrinsic. `entries`'s actual
    /// runtime representation is a `RuntimeListBox` (`kk_enum_make_entries_list`
    /// in RuntimeEnum.swift), so this panicked with KSWIFTK-LINK-0003 at
    /// runtime. `values()`/`enumValues<T>()` (`Array<T>`/`RuntimeArrayBox`) and
    /// `for (d in entries)` (iterator-based, not indexed) were unaffected,
    /// which is what made this a narrower bug than "EnumEntries is broken".
    /// Fixed by registering a `get(index: Int): T` operator on `EnumEntries<T>`
    /// that reuses the same `__kk_list_get` bridge `List<E>.get` already uses
    /// (on top of `EnumEntries<T> : List<T>` from DEADCODE-014, which alone
    /// was not enough to make `[]` itself resolve). Complements
    /// `testCodegenEnumValuesEntriesElementAccessEqualityAndWhen` (BUG-177,
    /// which covers `Array.get`/forEach/for-in but not `EnumEntries.get`).
    @Test
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
#endif

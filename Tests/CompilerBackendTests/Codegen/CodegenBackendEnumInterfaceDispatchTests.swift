#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// An enum entry that crosses an Any-erased collection/vararg boundary
/// (`listOf`, `arrayOf`, `vararg xs: I`) is boxed with `kk_enum_box_ordinal`
/// and must carry the same itable registrations as a direct `val i: I = E.A`
/// conversion: interface property getters, interface methods (including
/// interface default bodies), with the enum receiver unboxed back to its raw
/// ordinal before the member body runs. Before the fix, those boundaries
/// boxed without `SemaModule`, so only the interface->slot mapping was
/// registered and the first interface call panicked with "Virtual dispatch
/// failed: method not found in vtable/itable".
@Suite
struct CodegenBackendEnumInterfaceDispatchTests {

    @Test
    func testInterfacePropertyThroughListOf() throws {
        let source = """
        interface HasCode { val code: Int }
        enum class St(override val code: Int) : HasCode { OK(200), NF(404) }

        fun main() {
            val codes: List<HasCode> = listOf(St.OK, St.NF)
            println(codes.map { it.code })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumIfacePropListOf",
            expected: "[200, 404]\n"
        )
    }

    @Test
    func testInterfaceMethodsThroughCollectionsAndVararg() throws {
        let source = """
        interface Shape {
            val side: Int
            fun area(scale: Int): Int
            fun label(): String = "shape"
        }
        enum class Sq(override val side: Int) : Shape {
            SMALL(2), BIG(5);
            override fun area(scale: Int): Int = side * side * scale
        }
        fun total(vararg shapes: Shape): Int = shapes.sumOf { it.area(1) }

        fun main() {
            val shapes: List<Shape> = listOf(Sq.SMALL, Sq.BIG)
            println(shapes.map { it.area(2) })
            println(shapes.map { it.label() })
            val array: Array<Shape> = arrayOf(Sq.BIG)
            println(array.map { it.side })
            println(total(Sq.SMALL, Sq.BIG))
            val direct: Shape = Sq.BIG
            println(direct.area(1))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumIfaceMethodsCollections",
            expected: "[8, 50]\n[shape, shape]\n[5]\n29\n25\n"
        )
    }

    /// A class-level member overridden in an entry body must dispatch
    /// through the enum's `$enumEntryDispatch$` helper from the itable too,
    /// matching the statically typed `Sq.A.label()` call.
    @Test
    func testEntryBodyOverrideThroughInterface() throws {
        let source = """
        interface Shape { fun label(): String }
        enum class Sq : Shape {
            A { override fun label() = "a!" },
            B;
            override fun label(): String = "base"
        }

        fun main() {
            val shapes: List<Shape> = listOf(Sq.A, Sq.B)
            println(shapes.map { it.label() })
            val direct: Shape = Sq.A
            println(direct.label())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumIfaceEntryOverride",
            expected: "[a!, base]\na!\n"
        )
    }
}
#endif

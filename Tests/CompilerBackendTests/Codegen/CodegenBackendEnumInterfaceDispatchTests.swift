#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

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

    @Test
    func testEntryBodyPropertyOverrideThroughEnumReceiver() throws {
        let source = """
        interface HasValue { val value: String }
        interface MutableValue { var value: String }
        enum class Inferred : HasValue {
            A { override val value = "inferred" }
        }
        enum class Explicit : HasValue {
            A { override val value: String = "explicit" }
        }
        enum class Custom : HasValue {
            A { override val value: String get() = "custom" }
        }
        enum class Mutable : MutableValue {
            A { override var value = "before" }
        }

        fun main() {
            println(Inferred.A.value)
            println(Explicit.A.value)
            println(Custom.A.value)
            val widened: HasValue = Inferred.A
            println(widened.value)
            val mutable = Mutable.A
            mutable.value = "after"
            println(mutable.value)
            val mutableInterface: MutableValue = Mutable.A
            mutableInterface.value = "interface"
            println(mutableInterface.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumIfaceEntryPropertyOverride",
            expected: "inferred\nexplicit\ncustom\ninferred\nafter\ninterface\n"
        )
    }
}
#endif

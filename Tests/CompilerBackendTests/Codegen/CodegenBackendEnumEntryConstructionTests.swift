#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// Enum entries are constructed once, lazily on first access to the enum
/// class: constructor arguments are evaluated a single time (bound by label,
/// with defaults that see earlier parameters), and the class body's property
/// initializers and `init` blocks plus entry-body properties run once per
/// entry. Values live in per-entry storage behind the enum property helpers
/// (`KIRLoweringDriver+EnumEntryStorage.swift`).
@Suite
struct CodegenBackendEnumEntryConstructionTests {

    @Test
    func testConstructorArgumentsAreEvaluatedOnce() throws {
        let source = """
        var counter = 0
        fun next(): Int { counter++; return counter }
        enum class E(val id: Int) { A(next()), B(next()) }

        fun main() {
            println(counter)
            println(E.A.id)
            println(E.A.id)
            println(E.B.id)
            println(counter)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumCtorArgsOnce",
            expected: "0\n1\n1\n2\n2\n"
        )
    }

    @Test
    func testNamedArgumentsAndDefaultsReferringToEarlierParameters() throws {
        let source = """
        enum class C(val r: Int, val g: Int, val b: Int = r + 1) { X(g = 1, r = 2), Y(5, 6) }

        fun main() {
            println("${C.X.r} ${C.X.g} ${C.X.b}")
            println("${C.Y.r} ${C.Y.g} ${C.Y.b}")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumNamedArgsDefault",
            expected: "2 1 3\n5 6 6\n"
        )
    }

    /// `init` after the entry list's `;` was parsed as a third enum entry, so
    /// the block never ran (and `values()` grew a bogus `init` entry).
    @Test
    func testInitBlocksRunOnFirstAccess() throws {
        let source = """
        enum class E { A, B; init { println("init " + name) } }

        fun main() {
            println("start")
            println(E.A)
            println(E.values().size)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumInitBlock",
            expected: "start\ninit A\ninit B\nA\n2\n"
        )
    }

    @Test
    func testBodyPropertiesAreStoredPerEntry() throws {
        let source = """
        enum class E(val n: Int) {
            A(3), B(4);
            val sq = n * n
            var hits = 0
            val tag: String
            init { tag = name + sq }
            fun bump() { hits += 10 }
        }

        fun main() {
            E.A.hits++
            E.A.bump()
            E.B.hits = 5
            println(E.A.sq)
            println(E.B.sq)
            println(E.A.hits)
            println(E.B.hits)
            println(E.B.tag)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumBodyProperties",
            expected: "9\n16\n11\n5\nB16\n"
        )
    }

    @Test
    func testEntryBodyOverrideVal() throws {
        let source = """
        enum class Op {
            PLUS { override val sym = "+" },
            MINUS { override val sym = "-" };
            abstract val sym: String
        }

        fun main() {
            println(Op.PLUS.sym + Op.MINUS.sym)
            for (op in Op.entries) println(op.sym)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumEntryOverrideVal",
            expected: "+-\n+\n-\n"
        )
    }

    /// The itable getter registered for an interface property overridden by
    /// an enum constructor property used to read an instance field offset
    /// from the ordinal box and trip `kk_array_get_inbounds`.
    @Test
    func testInterfacePropertyOverriddenByConstructorPropertyThroughInterface() throws {
        let source = """
        interface HasCode { val code: Int }
        enum class St(override val code: Int) : HasCode { OK(200), NF(404) }

        fun main() {
            val h: HasCode = St.NF
            println(h.code)
            println(St.OK.code)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumInterfacePropertyOverride",
            expected: "404\n200\n"
        )
    }
}
#endif

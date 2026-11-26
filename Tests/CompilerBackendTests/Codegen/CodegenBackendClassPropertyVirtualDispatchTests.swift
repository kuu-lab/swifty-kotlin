#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendClassPropertyVirtualDispatchTests {

    @Test
    func testOverriddenBareDefaultAccessorsDispatchThroughGenericBase() throws {
        let source = try diffCaseSource("overridden_bare_property_accessors.kt")
            .replacingOccurrences(of: "    println(\"OK\")\n", with: "")
        for optLevel in [OptimizationLevel.O0, .O2] {
            try assertKotlinOutput(
                source,
                moduleName: "KUU3607BareDefaultAccessors",
                expected: "",
                optLevel: optLevel,
                includeStdlib: false,
                allowDefaultStdlibLibrary: false,
                prepareTestStdlibCache: false
            )
        }
    }

    @Test
    func testStoredPropertyReadThroughBaseTypedReference() throws {
        let source = """
        open class Base {
            open val p = "bp"
            open fun f() = "base"
        }
        class Derived : Base() {
            override val p = "dp"
            override fun f() = "derived"
        }
        fun main() {
            val b: Base = Derived()
            println(b.p)
            println(b.f())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug223StoredPropertyRead",
            expected: "dp\nderived\n"
        )
    }

    @Test
    func testCustomGetterOverrideReadThroughBaseTypedReference() throws {
        let source = """
        open class Base {
            open val p: String get() = "bp"
        }
        class Derived : Base() {
            override val p: String get() = "dp"
        }
        fun main() {
            val b: Base = Derived()
            println(b.p)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug223CustomGetterRead",
            expected: "dp\n"
        )
    }

    @Test
    func testCustomSetterOverrideWriteAndReadThroughBaseTypedReference() throws {
        let source = """
        open class Base {
            open var p: String = "base-init"
                set(value) { field = "base:" + value }
        }
        class Derived : Base() {
            override var p: String = "derived-init"
                set(value) { field = "derived:" + value }
        }
        fun main() {
            val b: Base = Derived()
            b.p = "x"
            println(b.p)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug223CustomSetterWrite",
            expected: "derived:x\n"
        )
    }

    @Test
    func testIntTypedStoredPropertyVirtualDispatchDoesNotCorruptBoxing() throws {
        let source = """
        open class Base {
            open var p: Int = 1
        }
        class Derived : Base() {
            override var p: Int = 2
        }
        fun main() {
            val b: Base = Derived()
            println(b.p)
            b.p = 99
            println(b.p)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug223IntPropertyBoxing",
            expected: "2\n99\n"
        )
    }

    @Test
    func testAbstractPropertyOverrideReadThroughBaseTypedReference() throws {
        let source = """
        abstract class Shape {
            abstract val area: Double
        }
        class Square(val side: Double) : Shape() {
            override val area: Double get() = side * side
        }
        fun main() {
            val s: Shape = Square(3.0)
            println(s.area)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug223AbstractPropertyRead",
            expected: "9.0\n"
        )
    }

    @Test
    func testAbstractPropertyReadInsideBaseMethodUsesGetterDispatch() throws {
        let source = """
        abstract class Shape {
            abstract val area: Double
            fun doubledArea(): Double = area * 2.0
        }
        class Square(private val side: Double) : Shape() {
            override val area: Double get() = side * side
        }
        fun main() {
            val shape: Shape = Square(3.0)
            println(shape.doubledArea())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug223AbstractPropertyInsideBaseMethod",
            expected: "18.0\n"
        )
    }

    @Test
    func testDirectlyTypedReceiverStillReadsItsOwnOverrideDirectly() throws {
        let source = """
        open class Base {
            open val p = "bp"
        }
        class Derived : Base() {
            override val p = "dp"
        }
        fun main() {
            val d = Derived()
            println(d.p)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug223DirectReceiverRead",
            expected: "dp\n"
        )
    }

    @Test
    func testCanonicalDiffCaseClassPropertyVirtualDispatch() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/class_property_virtual_dispatch.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try assertKotlinOutput(
            source,
            moduleName: "Bug223ClassPropertyVirtualDispatch",
            expected:
                """
                dp
                derived
                dp
                derived:x
                9.0
                """ + "\n"
        )
    }
}
#endif

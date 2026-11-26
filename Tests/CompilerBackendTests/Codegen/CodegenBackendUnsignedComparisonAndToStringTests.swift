#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendUnsignedComparisonAndToStringTests {

    @Test
    func testUnsignedComparisonHighBitSetULong() throws {
        let source = """
        fun main() {
            val small: ULong = 5uL
            val big: ULong = 17663719463477156090uL
            println(small >= 0uL)
            println(big >= 0uL)
            println(big > small)
            println(big >= small)
            println(small < big)
            println(small <= big)
            println(big < small)
            println(big <= small)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedComparisonHighBitSetULong",
            expected: """
            true
            true
            true
            true
            true
            true
            false
            false
            """ + "\n"
        )
    }

    @Test
    func testUnsignedCompareHelperBothHighBits() throws {
        let source = """
        @file:Suppress("INVISIBLE_REFERENCE", "INVISIBLE_MEMBER")
        package kotlin

        fun main() {
            println(ulongCompare(Long.MIN_VALUE, -1L))
            println(ulongCompare(-1L, Long.MIN_VALUE))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedCompareHelperBothHighBits",
            expected: """
            -1
            1
            """ + "\n"
        )
    }

    @Test
    func testUnsignedComparisonULongMaxValueBoundary() throws {
        let source = """
        fun main() {
            println(ULong.MAX_VALUE >= 0uL)
            println(ULong.MAX_VALUE > 0uL)
            println(0uL < ULong.MAX_VALUE)
            println(ULong.MAX_VALUE >= ULong.MAX_VALUE)
            println(ULong.MAX_VALUE <= ULong.MAX_VALUE)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedComparisonULongMaxValueBoundary",
            expected: """
            true
            true
            true
            true
            true
            """ + "\n"
        )
    }

    @Test
    func testUnsignedToStringHighBitSetULong() throws {
        let source = """
        fun main() {
            val big: ULong = 17663719463477156090uL
            println(big.toString())
            println(ULong.MAX_VALUE.toString())
            // 2^63 shares its raw bit pattern with the compiler's null
            // sentinel (Int.min); toString() must still render the real
            // unsigned value rather than the literal string "null".
            val boundary: ULong = 9223372036854775808uL
            println(boundary.toString())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedToStringHighBitSetULong",
            expected: """
            17663719463477156090
            18446744073709551615
            9223372036854775808
            """ + "\n"
        )
    }

    @Test
    func testUnsignedToStringRadixBoundaries() throws {
        let source = try diffCaseSource("unsigned_toString_radix.kt")
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedToStringRadixBoundaries",
            expected: """
            0
            0
            ff
            ff
            ffffffff
            8000000000000000
            1111111111111111111111111111111111111111111111111111111111111111
            11111111
            377
            1ekf
            invalid
            invalid
            invalid
            invalid
            """ + "\n"
        )
    }

    @Test
    func testUnsignedStringTemplateHighBitSetULong() throws {
        let source = """
        fun main() {
            val big: ULong = 17663719463477156090uL
            println("value=$big")
            println("concat=" + big)

            val nullableBig: ULong? = big
            println("nullable=$nullableBig")
            val nullableNone: ULong? = null
            println("isNull=$nullableNone")
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedStringTemplateHighBitSetULong",
            expected: """
            value=17663719463477156090
            concat=17663719463477156090
            nullable=17663719463477156090
            isNull=null
            """ + "\n"
        )
    }

    @Test
    func testUnsignedComparisonAndToStringUIntUnaffected() throws {
        let source = """
        fun main() {
            val small: UInt = 5u
            val big: UInt = UInt.MAX_VALUE
            println(small >= 0u)
            println(big >= 0u)
            println(big > small)
            println(big.toString())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedComparisonAndToStringUIntUnaffected",
            expected: """
            true
            true
            true
            4294967295
            """ + "\n"
        )
    }

    @Test
    func testDataClassToStringUnitProperty() throws {
        let source = """
        data class UnitHolder(val value: Unit)
        data class NullableUnitHolder(val value: Unit?)
        fun main() {
            val unit = UnitHolder(Unit)
            println(unit.toString())
            println(unit)
            println(unit.component1())

            println(NullableUnitHolder(Unit))
            println(NullableUnitHolder(null))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "DataClassToStringUnitProperty",
            expected: """
            UnitHolder(value=kotlin.Unit)
            UnitHolder(value=kotlin.Unit)
            kotlin.Unit
            NullableUnitHolder(value=kotlin.Unit)
            NullableUnitHolder(value=null)
            """ + "\n",
            allowDefaultStdlibLibrary: false,
            prepareTestStdlibCache: false
        )
    }

    @Test
    func testDataClassToStringFloatDoubleCharProperties() throws {
        let source = """
        data class Point(val x: Float, val y: Double, val label: Char)
        fun main() {
            val p = Point(1.5f, 2.75, 'A')
            println(p.toString())
            println(p)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "DataClassToStringFloatDoubleCharProperties",
            expected: """
            Point(x=1.5, y=2.75, label=A)
            Point(x=1.5, y=2.75, label=A)
            """ + "\n"
        )
    }

    @Test
    func testDataClassToStringNestedUserDefinedClassProperties() throws {
        let source = """
        data class Pt(val x: Int, val y: Int)
        data class Named(val name: String, val pt: Pt)
        class Label(val value: String) {
            override fun toString(): String = "label=$value"
        }
        data class WithLabel(val label: Label)
        open class Base {
            override fun toString(): String = "base"
        }
        class Child : Base() {
            override fun toString(): String = "child"
        }
        data class WithBase(val value: Base)
        fun main() {
            println(Pt(1, 2).toString())
            println(Named("n", Pt(1, 2)).toString())
            println(WithLabel(Label("custom")).toString())
            println(WithBase(Base()).toString())
            println(WithBase(Child()).toString())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "DataClassToStringNestedUserDefinedClassProperties",
            expected: """
            Pt(x=1, y=2)
            Named(name=n, pt=Pt(x=1, y=2))
            WithLabel(label=label=custom)
            WithBase(value=base)
            WithBase(value=child)
            """ + "\n"
        )
    }

    @Test
    func testDataClassToStringNullableFloatDoubleCharProperties() throws {
        let source = """
        data class NullablePoint(val x: Float?, val y: Double?, val label: Char?)
        fun main() {
            val real = NullablePoint(1.5f, 2.75, 'A')
            println(real.toString())
            println(real)

            val allNull = NullablePoint(null, null, null)
            println(allNull.toString())
            println(allNull)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "DataClassToStringNullableFloatDoubleCharProperties",
            expected: """
            NullablePoint(x=1.5, y=2.75, label=A)
            NullablePoint(x=1.5, y=2.75, label=A)
            NullablePoint(x=null, y=null, label=null)
            NullablePoint(x=null, y=null, label=null)
            """ + "\n"
        )
    }
}
#endif

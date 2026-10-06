@testable import CompilerCore
import Testing

@Suite
struct ValueClassIdentityEqualityTests {
    @Test(arguments: ["===", "!=="])
    func rejectsValueClassOperands(op: String) throws {
        let source = """
        @JvmInline value class Meters(val v: Int)
        @JvmInline value class Seconds(val v: Int)
        typealias Distance = Meters
        fun constructors() = Meters(5) \(op) Meters(5)
        fun same(a: Meters, b: Meters) = a \(op) b
        fun different(a: Meters, b: Seconds) = a \(op) b
        fun nullable(a: Meters?, b: Meters?) = a \(op) b
        fun mixed(a: Meters, b: Meters?) = a \(op) b
        fun anyRight(a: Meters, b: Any) = a \(op) b
        fun anyLeft(a: Any, b: Meters) = a \(op) b
        fun nullableAny(a: Meters?, b: Any?) = a \(op) b
        fun alias(a: Distance, b: Distance) = a \(op) b
        fun cast(a: Any, b: Meters) = (a as Meters) \(op) b
        fun inferred(a: Meters): Boolean {
            val local = a
            return local \(op) a
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 11, "Expected one error per prohibited comparison: \(errors)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0002" })
        #expect(errors.allSatisfy { $0.message.hasPrefix("Identity equality for arguments of types '") })
        #expect(errors.contains { $0.message == "Identity equality for arguments of types 'Meters?' and 'Meters?' is prohibited." })
        #expect(errors.contains { $0.message == "Identity equality for arguments of types 'Any' and 'Meters' is prohibited." })
    }

    @Test(arguments: ["===", "!=="])
    func preservesNullAndErasedComparisons(op: String) throws {
        let source = """
        @JvmInline value class Meters(val v: Int)
        class Reference
        fun nullRight(a: Meters?) = a \(op) null
        fun nullLeft(a: Meters?) = null \(op) a
        fun nonNullNull(a: Meters) = a \(op) null
        fun nullableNothing(a: Meters, b: Nothing?) = a \(op) b
        fun references(a: Reference, b: Reference) = a \(op) b
        fun nullableReferences(a: Reference?, b: Reference?) = a \(op) b
        fun <T> generic(a: T, b: T) = a \(op) b
        fun <T : Meters> bounded(a: T, b: T) = a \(op) b
        fun widened(a: Meters, b: Meters): Boolean {
            val x: Any = a
            val y: Any = b
            return x \(op) y
        }
        fun casts(a: Meters, b: Meters) = (a as Any) \(op) (b as Any)
        fun narrowed(a: Any, b: Any): Boolean {
            if (a is Meters && b is Meters) return a \(op) b
            return false
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Null, erased, generic and reference comparisons should remain accepted: \(errors)")
    }

    @Test func preservesStructuralEquality() throws {
        let source = """
        @JvmInline value class Meters(val v: Int)
        fun equal(a: Meters, b: Meters) = a == b
        fun notEqual(a: Meters, b: Meters) = a != b
        fun nullable(a: Meters?, b: Meters?) = a == b
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Value-class structural equality should remain accepted: \(errors)")
    }
}

@testable import CompilerCore
import Testing

@Suite
struct DistinctSingletonIdentityTests {
    @Test(arguments: ["===", "!=="])
    func rejectsDistinctSingletonTypesExceptSharedNull(op: String) throws {
        let context = makeContextFromSource("""
        object A
        object B
        typealias AliasA = A
        fun direct() = A \(op) B
        fun parameters(a: A, b: B) = a \(op) b
        fun aliases(a: AliasA, b: B) = a \(op) b
        fun leftNullable(a: A?, b: B) = a \(op) b
        fun rightNullable(a: A, b: B?) = a \(op) b
        fun bothNullable(a: A?, b: B?) = a \(op) b
        """)
        try runSema(context)
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 5, "\(errors)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0002" && $0.message.contains("unrelated singleton types") })
    }

    @Test(arguments: ["===", "!=="])
    func preservesSameSingletonNullWidenedAndSmartCastTypes(op: String) throws {
        let context = makeContextFromSource("""
        sealed class Base
        object A: Base()
        object B: Base()
        fun same(a: A, b: A) = a \(op) b
        fun sharedNull(a: A?, b: B?) = a \(op) b
        fun nullRight(a: A) = a \(op) null
        fun erased(a: Any, b: Any) = a \(op) b
        fun base(a: Base, b: Base) = a \(op) b
        fun cast() = (A as Any) \(op) (B as Any)
        fun narrowed(a: Any, b: Any): Boolean {
            if (a is A && b is B) return a \(op) b
            return false
        }
        """)
        try runSema(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }
}

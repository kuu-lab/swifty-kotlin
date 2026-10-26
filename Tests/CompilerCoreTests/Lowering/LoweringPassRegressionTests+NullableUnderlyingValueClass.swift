#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// A value class whose underlying representation can carry null (`String?`,
/// another nullable-underlying value class, or an erased type parameter)
/// erases to that payload type, so a non-null wrapper holding a null payload
/// is indistinguishable from Kotlin `null` if `V?`/Any slots keep the bare
/// pointer. These assert the lowered KIR routes such value classes through a
/// dedicated nominal box — kk_value_class_box wraps the payload on `V` ->
/// `V?`/Any boundaries and kk_value_class_unbox idempotently recovers the
/// payload on the way back — instead of the primitive box+tag path or a
/// verbatim copy that conflates wrapper nullness with payload nullness.
extension LoweringPassRegressionTests {
    @Test
    func testNullableUnderlyingValueClassInitBoxesIntoNullableSlot() throws {
        let source = """
        @JvmInline
        value class V(val x: String?)
        fun store(): V? = V(null)
        """
        let callees = try loweredCallees(for: source, function: "store", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.valueClassBox.name), "V -> V? must box the payload into the nominal value-class box: \(callees)")
        #expect(!callees.contains(RuntimeCall.tagValueClassBox.name), "Nullable-underlying value classes must not use the primitive tag path: \(callees)")
    }

    @Test
    func testNullableUnderlyingValueClassUnwrapUnboxes() throws {
        let source = """
        @JvmInline
        value class V(val x: String?)
        fun unwrap(v: V?): V = v!!
        """
        let callees = try loweredCallees(for: source, function: "unwrap", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.valueClassUnbox.name), "V? -> V must unbox the nominal box back to the payload: \(callees)")
    }

    @Test
    func testNullableUnderlyingValueClassArgumentUnboxesForNonNullParameter() throws {
        let source = """
        @JvmInline
        value class V(val x: String?)
        fun take(v: V): String? = v.x
        fun call(v: V?): String? = take(v!!)
        """
        let callees = try loweredCallees(for: source, function: "call", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.valueClassUnbox.name), "Passing V? where V is expected must unbox: \(callees)")
    }

    @Test
    func testNullableUnderlyingValueClassSafeReadUsesInboundsFieldAccess() throws {
        let source = """
        @JvmInline
        value class V(val x: String?)
        fun read(v: V?): String? = v?.x
        """
        let callees = try loweredCallees(for: source, function: "read", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.arrayGetInbounds.name), "v?.x must read the payload field out of the value-class box: \(callees)")
    }

    @Test
    func testNestedNullableValueClassSafeCallBoxesMemberResult() throws {
        let source = """
        @JvmInline
        value class V(val x: String?)
        @JvmInline
        value class V2(val x: V)
        fun read(n: V2?): V? = n?.x
        """
        let callees = try loweredCallees(for: source, function: "read", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.arrayGetInbounds.name), "n?.x must read the V field out of the V2 box: \(callees)")
        #expect(callees.contains(RuntimeCall.valueClassBox.name), "The non-null V member result must be boxed before merging into V?: \(callees)")
    }

    @Test
    func testNestedNullableValueClassChainedSafeCallBoxesMemberResult() throws {
        let source = """
        @JvmInline
        value class V(val x: String?)
        @JvmInline
        value class V2(val x: V)
        fun read(n: V2?): String? = n?.x?.x
        """
        let callees = try loweredCallees(for: source, function: "read", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.valueClassBox.name), "n?.x must produce a boxed V before the chained ?.x field read: \(callees)")
        #expect(callees.filter { $0 == RuntimeCall.arrayGetInbounds.name }.count >= 2, "Both ?.x levels must read fields through value-class boxes: \(callees)")
    }

    @Test
    func testNullableUnderlyingValueClassAnyBoundaryUsesValueClassBox() throws {
        let source = """
        @JvmInline
        value class V(val x: String?)
        fun erase(): Any = V(null)
        """
        let callees = try loweredCallees(for: source, function: "erase", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.valueClassBox.name), "V -> Any must keep the nominal value-class identity in its box: \(callees)")
        #expect(!callees.contains(RuntimeCall.tagValueClassBox.name), "V -> Any must not tag a bare payload pointer: \(callees)")
    }

    @Test
    func testNullableUnderlyingValueClassFieldReadDoesNotReboxPayload() throws {
        let source = """
        @JvmInline
        value class V(val x: Any?)
        fun isNull(v: V): Boolean = v.x == null
        """
        let callees = try loweredCallees(for: source, function: "isNull", includeStdlib: false)
        #expect(!callees.contains(RuntimeCall.valueClassBox.name), "Reading V.x must preserve the raw nullable payload instead of boxing V: \(callees)")
    }

    @Test
    func testNullableUnderlyingValueClassMemberCallUnboxesReceiver() throws {
        let source = """
        @JvmInline
        value class V(val x: String?) {
            fun tag(): String = "V(" + (x ?: "<null>") + ")"
        }
        fun read(v: V?): String? = v?.tag()
        """
        let callees = try loweredCallees(for: source, function: "read", includeStdlib: false)
        #expect(callees.contains(RuntimeCall.valueClassUnbox.name), "Calling a member on V? must unbox the receiver before dispatch: \(callees)")
    }

    @Test
    func testNonNullableUnderlyingValueClassKeepsExistingRepresentation() throws {
        let source = """
        @JvmInline
        value class S(val x: String)
        fun store(s: S): S? = s
        """
        let callees = try loweredCallees(for: source, function: "store", includeStdlib: false)
        #expect(!callees.contains(RuntimeCall.valueClassBox.name), "A value class whose payload cannot be null must keep its existing representation: \(callees)")
        #expect(!callees.contains(RuntimeCall.valueClassUnbox.name), "A value class whose payload cannot be null must not emit kk_value_class_unbox: \(callees)")
    }

    @Test
    func testConcreteGenericValueClassUsesInstantiatedUnderlyingTypeAtGenericBoundary() throws {
        let source = """
        annotation class JvmInline
        @JvmInline
        value class IC<T: Int>(val i: T) {
            init { counter += i }
        }
        var counter = 0
        fun <T> id(t: T) = t
        fun pass() {
            val ic = IC(42)
            counter = 0
            id(ic)
        }
        """
        let callees = try loweredCallees(for: source, function: "pass", includeStdlib: false)
        #expect(
            callees.contains(RuntimeCall.tagValueClassBox.name),
            "IC<Int> has a non-null Int payload and must use primitive boxing with its value-class tag: \(callees)"
        )
        #expect(
            !callees.contains(RuntimeCall.valueClassBox.name),
            "IC<Int> must not use the nominal box reserved for nullable underlying representations: \(callees)"
        )
    }

    @Test
    func testErasedGenericValueClassStillUsesNominalBoxAtGenericBoundary() throws {
        let source = """
        annotation class JvmInline
        @JvmInline
        value class Box<T>(val value: T)
        fun <T> id(value: T): T = value
        fun <T> erase(value: Box<T>): Any = id(value)
        """
        let callees = try loweredCallees(for: source, function: "erase", includeStdlib: false)
        #expect(
            callees.contains(RuntimeCall.valueClassBox.name),
            "An erased generic payload may carry null and must retain the nominal value-class box: \(callees)"
        )
        #expect(
            !callees.contains(RuntimeCall.tagValueClassBox.name),
            "An erased generic payload must not use the primitive box-and-tag route: \(callees)"
        )
    }

    private func loweredCallees(for source: String, function functionName: String, includeStdlib: Bool = true) throws -> [String] {
        var callees: [String] = []
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .object, includeStdlib: includeStdlib)
            try runToLowering(ctx)

            for path in paths {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(errors.isEmpty, "Unexpected errors for \(path): \(errors.map(\.message))")
            }

            let module: KIRModule = try #require(ctx.kir)
            let interner = ctx.interner
            let function = try findKIRFunction(named: functionName, in: module, interner: interner)
            callees = extractCallees(from: function.body, interner: interner)
        }
        return callees
    }
}
#endif

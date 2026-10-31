#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// KUU-3899: a `.nullAssert` (`x!!`, `as`-implied asserts, `implicitNotNull`)
/// whose operand's static type is non-null AND whose runtime slot cannot
/// encode a null value must not emit `kk_op_notnull`. That probe compares the
/// raw slot against the null-sentinel bit pattern, which is a legitimate
/// value for these operands — `Long.MIN_VALUE`/`ULong` 2^63/`-0.0` for raw
/// primitives, and `V(null)` or a sentinel-colliding payload for a value
/// class kept unboxed — never a null reference. Nullable, platform, erased,
/// and reference slots keep the probe, and so do value classes that stay
/// boxed (interface supertypes → a real object handle).
extension LoweringPassRegressionTests {
    @Test
    func testNullAssertOnNonNullUnboxedValueClassSkipsProbe() throws {
        let source = """
        value class V(val x: String?)
        fun read(v: V): String? = (v!!).x
        """
        let callees = try loweredCallees(for: source, function: "read", includeStdlib: false)
        #expect(!callees.contains("kk_op_notnull"), "v!! on a non-null unboxed value class must not probe the raw payload slot: \(callees)")
    }

    @Test
    func testNullAssertOnSentinelCollidingValueClassSkipsProbe() throws {
        let source = """
        value class VL(val x: Long)
        fun read(v: VL): Long = (v!!).x
        """
        let callees = try loweredCallees(for: source, function: "read", includeStdlib: false)
        #expect(!callees.contains("kk_op_notnull"), "v!! on a value class whose flat payload can collide with the null sentinel (Long.MIN_VALUE) must not probe it: \(callees)")
    }

    @Test
    func testNullAssertOnNonNullPrimitiveSkipsProbe() throws {
        let source = """
        fun read(v: Long): Long = v!!
        """
        let callees = try loweredCallees(for: source, function: "read", includeStdlib: false)
        #expect(!callees.contains("kk_op_notnull"), "v!! on a non-null primitive must not probe the raw slot (Long.MIN_VALUE is a valid value): \(callees)")
    }

    @Test
    func testNullAssertOnNullableValueClassKeepsProbe() throws {
        let source = """
        value class V(val x: String?)
        fun read(v: V?): String? = v!!.x
        """
        let callees = try loweredCallees(for: source, function: "read", includeStdlib: false)
        #expect(callees.contains("kk_op_notnull"), "v!! on V? must still probe the nominal box: \(callees)")
        // The probe must run on the delivered box BEFORE it is unboxed to the
        // flat payload — `V(null)` is a non-null box wrapping a null payload,
        // and unboxing first would make the sentinel probe fire spuriously.
        if let probeIdx = callees.firstIndex(of: "kk_op_notnull"),
           let unboxIdx = callees.firstIndex(of: "kk_value_class_unbox") {
            #expect(probeIdx < unboxIdx, "kk_op_notnull must probe the box before kk_value_class_unbox flattens it: \(callees)")
        }
    }

    @Test
    func testNullAssertOnNullablePrimitiveKeepsProbe() throws {
        let source = """
        fun read(v: Int?): Int = v!!
        """
        let callees = try loweredCallees(for: source, function: "read", includeStdlib: false)
        #expect(callees.contains("kk_op_notnull"), "v!! on a nullable primitive must keep the box/sentinel probe: \(callees)")
    }

    @Test
    func testNullAssertOnNullableReferenceKeepsProbe() throws {
        let source = """
        fun read(v: String?): String = v!!
        """
        let callees = try loweredCallees(for: source, function: "read", includeStdlib: false)
        #expect(callees.contains("kk_op_notnull"), "v!! on a nullable reference must keep the probe: \(callees)")
    }

    @Test
    func testNullAssertOnInterfaceImplementingValueClassKeepsProbe() throws {
        let source = """
        interface HasName { fun name(): String }
        value class VI(val x: String) : HasName {
            override fun name(): String = x
        }
        fun read(v: VI): String = v!!.name()
        """
        let callees = try loweredCallees(for: source, function: "read", includeStdlib: false)
        #expect(callees.contains("kk_op_notnull"), "A value class that stays boxed (interface supertypes) keeps a real object probe: \(callees)")
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

#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    /// Callee names invoked inside the synthesized `equals` body of the named
    /// data class. The synthesized body only exists after `LoweringPhase`
    /// (DataEnumSealedSynthesisPass), so callers must run `runToLowering`.
    func dataClassEqualsCalleeNames(
        of nominalName: String,
        in module: KIRModule,
        sema: SemaModule,
        interner: StringInterner
    ) throws -> [String] {
        let equals = try #require(sema.symbols.lookupAll(fqName: [
            interner.intern(nominalName), interner.intern("equals"),
        ]).first { sema.symbols.symbol($0)?.kind == .function })
        let function = try #require(module.arena.function(for: equals))
        return function.body.compactMap { instruction -> String? in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return nil }
            return interner.resolve(callee)
        }
    }

    @Test
    func dataClassEqualsUsesCanonicalDoubleEquality() throws {
        let context = makeContextFromSource("""
        data class D(val x: Double)
        """)
        try runToLowering(context)
        #expect(!context.diagnostics.hasError)
        let sema = try #require(context.sema)
        let module = try #require(context.kir)

        let callees = try dataClassEqualsCalleeNames(
            of: "D", in: module, sema: sema, interner: context.interner
        )
        #expect(callees.contains("kk_double_equals"))
        #expect(!callees.contains("kk_op_eq"))
    }

    @Test
    func dataClassEqualsUsesCanonicalFloatEquality() throws {
        let context = makeContextFromSource("""
        data class F(val x: Float)
        """)
        try runToLowering(context)
        #expect(!context.diagnostics.hasError)
        let sema = try #require(context.sema)
        let module = try #require(context.kir)

        let callees = try dataClassEqualsCalleeNames(
            of: "F", in: module, sema: sema, interner: context.interner
        )
        #expect(callees.contains("kk_float_equals"))
        #expect(!callees.contains("kk_op_eq"))
    }

    @Test
    func dataClassEqualsKeepsOpEqForIntegerProperties() throws {
        let context = makeContextFromSource("""
        data class M(val i: Int, val l: Long, val d: Double)
        """)
        try runToLowering(context)
        #expect(!context.diagnostics.hasError)
        let sema = try #require(context.sema)
        let module = try #require(context.kir)

        let callees = try dataClassEqualsCalleeNames(
            of: "M", in: module, sema: sema, interner: context.interner
        )
        #expect(callees.filter { $0 == "kk_op_eq" }.count == 2)
        #expect(callees.filter { $0 == "kk_double_equals" }.count == 1)
    }
}
#endif

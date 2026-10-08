#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-848: preserve the shared checked allocation and primitive-element store
/// lowering for FloatArray constructors without adding a FloatArray-specific ABI.
@Suite
struct FloatArrayConstructorLoweringTests {
    @Test
    func constructorsLowerToSharedArrayRuntimeCalls() throws {
        let ctx = makeContextFromSource("""
        fun initialize(): FloatArray = FloatArray(4) { index ->
            if (index == 0) 1.5f else 2.5f
        }
        fun allocate(): FloatArray = FloatArray(3)
        """)
        try runToLowering(ctx)

        let module = try #require(ctx.kir)
        let initializedBody = try findKIRFunctionBody(named: "initialize", in: module, interner: ctx.interner)
        let initializedCalls = kirCalls(in: initializedBody)
        let allocations = kirCalls(to: .arrayNewChecked, in: initializedBody, interner: ctx.interner)
        #expect(!allocations.isEmpty)
        #expect(!kirCalls(to: .arraySet, in: initializedBody, interner: ctx.interner).isEmpty)
        #expect(!initializedCalls.contains { $0.callee == KnownCompilerNames(interner: ctx.interner).floatArray })

        #expect(allocations.allSatisfy { $0.canThrow })

        let sizeOnlyBody = try findKIRFunctionBody(named: "allocate", in: module, interner: ctx.interner)
        let sizeOnlyCalls = kirCalls(in: sizeOnlyBody)
        #expect(!kirCalls(to: .arrayNewChecked, in: sizeOnlyBody, interner: ctx.interner).isEmpty)
        #expect(kirCalls(to: .arraySet, in: sizeOnlyBody, interner: ctx.interner).isEmpty)
        #expect(!sizeOnlyCalls.contains { $0.callee == KnownCompilerNames(interner: ctx.interner).floatArray })
    }
}
#endif

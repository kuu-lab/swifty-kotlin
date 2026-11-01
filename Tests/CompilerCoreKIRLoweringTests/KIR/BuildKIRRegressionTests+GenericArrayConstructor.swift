#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    @Test
    func genericArrayConstructorsLowerToCheckedAllocation() throws {
        let sources = [
            """
            package genericarray
            fun initialized() = Array(3) { it * 2 }
            fun sized(): Array<String?> = Array(2)
            """
        ]
        let ctx = makeContextFromSources(sources)
        try runToLowering(ctx)
        let module = try #require(ctx.kir)

        let initializedBody = try findKIRFunctionBody(
            named: "initialized", in: module, interner: ctx.interner
        )
        let sizedBody = try findKIRFunctionBody(
            named: "sized", in: module, interner: ctx.interner
        )

        let initializedCallees = extractCallees(from: initializedBody, interner: ctx.interner)
        let sizedCallees = extractCallees(from: sizedBody, interner: ctx.interner)
        #expect(initializedCallees.contains(runtimeCallee(.arrayNewChecked)))
        #expect(initializedCallees.contains(runtimeCallee(.arraySet)))
        // Allocation is followed by the array's Cloneable/Serializable ancestry
        // registration (#11647) and its runtime component tag (#8313).
        #expect(sizedCallees == [
            runtimeCallee(.arrayNewChecked),
            runtimeCallee(.arrayTagType),
            "kk_type_register_iface",
            "kk_type_register_super",
            runtimeCallee(.arrayTagType),
            "__kk_array_component_type",
            "__kk_array_tag_component",
        ])

        let throwFlags = extractThrowFlags(from: sizedBody, interner: ctx.interner)
        #expect(throwFlags[runtimeCallee(.arrayNewChecked)]?.allSatisfy { $0 } == true)
        #expect(throwFlags[runtimeCallee(.arrayTagType)]?.allSatisfy { !$0 } == true)
    }
}
#endif

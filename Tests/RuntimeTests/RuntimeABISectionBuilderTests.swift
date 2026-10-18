#if canImport(Testing)
@testable import RuntimeABI
import Testing

/// `RuntimeABISectionBuilder` must produce exactly the spec the long-hand
/// `RuntimeABIFunctionSpec(...)` literal produced, for every field `specVersion` hashes.
@Suite
struct RuntimeABISectionBuilderTests {
    private let abi = RuntimeABISectionBuilder("Demo")

    @Test
    func nonThrowingBareNamesDefaultToIntptr() {
        let expected = RuntimeABIFunctionSpec(
            name: "kk_demo_add",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Demo",
            isThrowing: false
        )
        #expect(abi.nt("kk_demo_add", "a b") == expected)
    }

    @Test
    func bareOutThrownIsNullableIntptrPointer() {
        let expected = RuntimeABIFunctionSpec(
            name: "kk_demo_div",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Demo"
        )
        #expect(abi.th("kk_demo_div", "lhs rhs outThrown") == expected)
    }

    @Test
    func explicitTypeOverridesTheOutThrownShorthand() {
        let spec = abi.th("kk_demo_odd", "outThrown:intptr")
        #expect(spec.parameters == [RuntimeABIParameter(name: "outThrown", type: .intptr)])
    }

    /// Existing data has `isThrowing: true` specs without an `outThrown` parameter; `th` must not
    /// add one, otherwise converting a file would change its `specVersion`.
    @Test
    func throwingDoesNotImplyOutThrown() {
        let spec = abi.th("kk_demo_ne", "lhs rhs")
        #expect(spec.isThrowing)
        #expect(spec.parameters.map(\.name) == ["lhs", "rhs"])
    }

    @Test
    func typedParametersReturnTypeAndRawBoolean() {
        let expected = RuntimeABIFunctionSpec(
            name: "kk_demo_flag",
            parameters: [
                RuntimeABIParameter(name: "msg", type: .constUInt8Pointer),
                RuntimeABIParameter(name: "len", type: .int32),
            ],
            returnType: .int32,
            section: "Demo",
            isThrowing: false,
            returnsRawBoolean: true
        )
        #expect(abi.nt("kk_demo_flag", "msg:constUInt8Pointer len:int32", ret: .int32, raw: true) == expected)
    }

    @Test
    func missingParameterStringMeansNoParameters() {
        let spec = abi.nt("kk_demo_noargs", ret: .void)
        #expect(spec.parameters.isEmpty)
        #expect(spec.returnType == .void)
    }

    /// Tokens are the `RuntimeABICType` case names, so no second table can drift out of sync.
    @Test
    func everyCTypeIsSpellableAsAParameterType() {
        #expect(String(describing: RuntimeABICType.intptr) == "intptr")
        for type in RuntimeABICType.allCases {
            let spec = abi.th("kk_demo_each", "p:\(type)")
            #expect(spec.parameters == [RuntimeABIParameter(name: "p", type: type)])
        }
    }
}
#endif

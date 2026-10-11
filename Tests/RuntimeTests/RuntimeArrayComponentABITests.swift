import RuntimeABI
import Testing

@Suite
struct RuntimeArrayComponentABITests {
    @Test
    func privateComponentBridgesKeepPointerSizedABIAndTypedKParameterArity() throws {
        let expected: [(String, Int)] = [("__kk_array_component_type", 2), ("__kk_array_tag_component", 2),
            ("__kk_array_new_same_component", 2), ("__kk_kparameter_set_array_component", 2)]
        let functions = RuntimeABISpec.arrayFunctions + RuntimeABISpec.kParameterFunctions
        for (name, arity) in expected {
            let spec = try #require(functions.first { $0.name == name })
            #expect(spec.parameters.count == arity)
            #expect(spec.parameters.allSatisfy { $0.type == .intptr })
            #expect(spec.returnType == .intptr && !spec.isThrowing)
        }
        let parameter = try #require(functions.first { $0.name == "__kk_kparameter_create_typed" })
        #expect(parameter.parameters.count == 7, "existing public parameter registration ABI stays intact")
    }
}

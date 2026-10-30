@testable import CompilerCore
import Testing

extension TypeSystemTests {
    @Test
    func functionLUBJoinsCallableReferenceReturnTypes() {
        let types = TypeSystem()
        let stringType = types.stringType
        let intType = types.intType
        let booleanType = types.booleanType
        let intReference = types.make(.functionType(FunctionType(
            params: [stringType],
            returnType: intType,
            isCallableReference: true
        )))
        let booleanReference = types.make(.functionType(FunctionType(
            params: [stringType],
            returnType: booleanType,
            isCallableReference: true
        )))
        let expected = types.make(.functionType(FunctionType(
            params: [stringType],
            returnType: types.anyType,
            isCallableReference: false
        )))

        #expect(types.lub([intReference, booleanReference]) == expected)
        #expect(types.lub([booleanReference, intReference]) == expected)
        #expect(types.isSubtype(intReference, expected))
        #expect(types.isSubtype(booleanReference, expected))
    }

    @Test
    func functionLUBPreservesAnExistingDominatingCallableReferenceType() {
        let types = TypeSystem()
        let narrowReference = types.make(.functionType(FunctionType(
            params: [types.stringType],
            returnType: types.intType,
            isCallableReference: true
        )))
        let dominatingReference = types.make(.functionType(FunctionType(
            params: [types.stringType],
            returnType: types.anyType,
            isCallableReference: true
        )))

        #expect(types.lub([narrowReference, dominatingReference]) == dominatingReference)
    }

    @Test
    func functionLUBNormalizesReceiverToLeadingParameter() {
        let types = TypeSystem()
        let receiverIntReference = types.make(.functionType(FunctionType(
            receiver: types.stringType,
            params: [],
            returnType: types.intType,
            isCallableReference: true
        )))
        let receiverBooleanReference = types.make(.functionType(FunctionType(
            receiver: types.stringType,
            params: [],
            returnType: types.booleanType,
            isCallableReference: true
        )))
        let expected = types.make(.functionType(FunctionType(
            params: [types.stringType],
            returnType: types.anyType,
            isCallableReference: false
        )))

        #expect(types.lub([receiverIntReference, receiverBooleanReference]) == expected)
        #expect(types.isSubtype(receiverIntReference, expected))
        #expect(types.isSubtype(receiverBooleanReference, expected))
    }

    @Test
    func functionLUBUsesGreatestLowerBoundForInputs() {
        let types = TypeSystem()
        let broadInput = types.make(.functionType(FunctionType(
            params: [types.anyType],
            returnType: types.intType
        )))
        let narrowInput = types.make(.functionType(FunctionType(
            params: [types.stringType],
            returnType: types.booleanType
        )))
        let expected = types.make(.functionType(FunctionType(
            params: [types.stringType],
            returnType: types.anyType
        )))

        #expect(types.lub([broadInput, narrowInput]) == expected)
        #expect(types.lub([narrowInput, broadInput]) == expected)
        #expect(types.isSubtype(broadInput, expected))
        #expect(types.isSubtype(narrowInput, expected))
    }

    @Test
    func functionLUBRetainsIncompatibleInputConstraints() {
        let types = TypeSystem()
        let stringInput = types.make(.functionType(FunctionType(
            params: [types.stringType],
            returnType: types.intType
        )))
        let intInput = types.make(.functionType(FunctionType(
            params: [types.intType],
            returnType: types.booleanType
        )))
        let joined = types.lub([stringInput, intInput])
        guard case let .functionType(function) = types.kind(of: joined),
              let parameter = function.params.first,
              case let .intersection(parts) = types.kind(of: parameter)
        else {
            Issue.record("Incompatible inputs should keep their intersection constraint.")
            return
        }

        #expect(Set(parts) == Set([types.stringType, types.intType]))
        #expect(types.isSubtype(stringInput, joined))
        #expect(types.isSubtype(intInput, joined))
        #expect(!types.isSubtype(types.stringType, parameter))
        #expect(!types.isSubtype(types.intType, parameter))
    }

    @Test
    func functionLUBRecursivelyJoinsFunctionReturnTypes() {
        let types = TypeSystem()
        let intProducer = types.make(.functionType(FunctionType(params: [], returnType: types.intType)))
        let booleanProducer = types.make(.functionType(FunctionType(params: [], returnType: types.booleanType)))
        let left = types.make(.functionType(FunctionType(params: [types.stringType], returnType: intProducer)))
        let right = types.make(.functionType(FunctionType(params: [types.stringType], returnType: booleanProducer)))
        let expectedProducer = types.make(.functionType(FunctionType(params: [], returnType: types.anyType)))
        let expected = types.make(.functionType(FunctionType(params: [types.stringType], returnType: expectedProducer)))

        #expect(types.lub([left, right]) == expected)
        #expect(types.lub([right, left]) == expected)
    }

    @Test
    func functionLUBDoesNotJoinDifferentAritiesOrSuspendShapes() {
        let types = TypeSystem()
        let zeroArgument = types.make(.functionType(FunctionType(params: [], returnType: types.intType)))
        let oneArgument = types.make(.functionType(FunctionType(params: [types.stringType], returnType: types.booleanType)))
        let suspend = types.make(.functionType(FunctionType(params: [], returnType: types.booleanType, isSuspend: true)))

        #expect(types.lub([zeroArgument, oneArgument]) == types.anyType)
        #expect(types.lub([zeroArgument, suspend]) == types.anyType)
    }
}

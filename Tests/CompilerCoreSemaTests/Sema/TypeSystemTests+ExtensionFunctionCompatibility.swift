@testable import CompilerCore
import Testing

extension TypeSystemTests {
    @Test(arguments: [false, true])
    func testFunctionReceiverMatchesLeadingParameter(isSuspend: Bool) {
        let types = TypeSystem()
        let int = types.make(.primitive(.int, .nonNull))
        let extensionType = types.make(.functionType(FunctionType(
            receiver: types.stringType, params: [int], returnType: int,
            isSuspend: isSuspend
        )))
        let ordinaryType = types.make(.functionType(FunctionType(
            params: [types.stringType, int], returnType: int,
            isSuspend: isSuspend
        )))
        #expect(types.isSubtype(extensionType, ordinaryType))
        #expect(types.isSubtype(ordinaryType, extensionType))

        let widerReceiver = types.make(.functionType(FunctionType(
            params: [types.anyType, int], returnType: int,
            isSuspend: isSuspend
        )))
        #expect(types.isSubtype(widerReceiver, extensionType))
        #expect(!types.isSubtype(extensionType, widerReceiver))

        let wrongReceiver = types.make(.functionType(FunctionType(
            params: [int, int], returnType: int, isSuspend: isSuspend
        )))
        #expect(!types.isSubtype(wrongReceiver, extensionType))
        let wrongSuspend = types.make(.functionType(FunctionType(
            params: [types.stringType, int], returnType: int,
            isSuspend: !isSuspend
        )))
        #expect(!types.isSubtype(wrongSuspend, extensionType))
        #expect(!types.isSubtype(types.makeNullable(ordinaryType), extensionType))
        #expect(types.isSubtype(ordinaryType, types.makeNullable(extensionType)))
    }

    @Test
    func testFunctionReceiverCompatibilityPreservesContextReceivers() {
        let types = TypeSystem()
        let int = types.make(.primitive(.int, .nonNull))
        let extensionType = types.make(.functionType(FunctionType(
            contextReceivers: [int], receiver: types.stringType,
            params: [], returnType: int, isSuspend: true
        )))
        let ordinaryType = types.make(.functionType(FunctionType(
            contextReceivers: [int], params: [types.stringType],
            returnType: int, isSuspend: true
        )))
        let noContext = types.make(.functionType(FunctionType(
            params: [int, types.stringType], returnType: int, isSuspend: true
        )))
        #expect(types.isSubtype(extensionType, ordinaryType))
        #expect(types.isSubtype(ordinaryType, extensionType))
        #expect(!types.isSubtype(extensionType, noContext))
        #expect(!types.isSubtype(noContext, extensionType))
    }
}

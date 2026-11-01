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
    func testFunctionReceiverCompatibilityFoldsContextReceivers() {
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
        // Since KUU-3175 context receivers and a receiver fold into leading
        // function parameters, `context(Int) String.() -> Int` has the same
        // effective shape as `(Int, String) -> Int`; use a mismatched
        // parameter order for the negative assertions.
        let noContext = types.make(.functionType(FunctionType(
            params: [types.stringType, int], returnType: int, isSuspend: true
        )))
        #expect(types.isSubtype(extensionType, ordinaryType))
        #expect(types.isSubtype(ordinaryType, extensionType))
        // kotlinc folds context receivers and a receiver into the leading
        // function-parameter list: `context(Int) String.() -> Int`,
        // `context(Int) (String) -> Int`, and `(Int, String) -> Int` share
        // the `(Int, String) -> Int` shape and are mutual subtypes
        // (verified against kotlinc 2.4.20; KUU-3175, KUU-4061).
        #expect(types.isSubtype(extensionType, noContext))
        #expect(types.isSubtype(noContext, extensionType))

        // Folding must not drop the context slot: a plain type missing the
        // leading Int parameter has a different arity and must not match.
        let missingContextSlot = types.make(.functionType(FunctionType(
            params: [types.stringType], returnType: int, isSuspend: true
        )))
        #expect(!types.isSubtype(extensionType, missingContextSlot))
        #expect(!types.isSubtype(missingContextSlot, extensionType))

        // The folded context slot is a normal contravariant parameter
        // position: `context(Any)` accepts where `context(Int)` is expected.
        let widerContext = types.make(.functionType(FunctionType(
            contextReceivers: [types.anyType], receiver: types.stringType,
            params: [], returnType: int, isSuspend: true
        )))
        #expect(types.isSubtype(widerContext, extensionType))
        #expect(!types.isSubtype(extensionType, widerContext))
    }
}

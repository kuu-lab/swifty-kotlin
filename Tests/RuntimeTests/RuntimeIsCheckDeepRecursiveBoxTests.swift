import Foundation
@testable import Runtime
import Testing

// KUU-3701: the DeepRecursive trampoline's scope/function boxes are opaque
// runtime objects that stand in for kotlin.DeepRecursiveScope /
// kotlin.DeepRecursiveFunction. They carry no object type metadata, so
// nominal `is`/`as` checks recover their identity through
// runtimeDeepRecursiveNominalTypeID — including the receiver cast emitted by
// suspend function value adapters for `DeepRecursiveScope<T, R>.() -> R`.
@Suite(.runtimeIsolation(.gcAndMetadata))
struct RuntimeIsCheckDeepRecursiveBoxTests {
    private func nominalToken(_ name: String) -> Int {
        Int(6 | (runtimeStableNominalTypeID(fqName: name) << 9))
    }

    private func makeFunctionBox() -> RuntimeDeepRecursiveFunctionBox {
        RuntimeDeepRecursiveFunctionBox(
            fnPtr: 0,
            functionID: 0,
            closureRaw: 0,
            launcherArgCount: 2
        )
    }

    @Test
    func scopeBoxAnswersDeepRecursiveScopeChecks() {
        let scope = registerRuntimeObject(
            RuntimeDeepRecursiveScopeBox(function: makeFunctionBox()) as AnyObject
        )
        let scopeToken = nominalToken("kotlin.DeepRecursiveScope")
        #expect(kk_op_is(scope, scopeToken) == 1)
        #expect(kk_op_is(scope, nominalToken("kotlin.DeepRecursiveFunction")) == 0)
        #expect(kk_op_is(scope, nominalToken("kotlin.String")) == 0)
        var thrown = 0
        #expect(kk_op_cast(scope, scopeToken, &thrown) == scope)
        #expect(thrown == 0)
        _ = kk_op_cast(scope, nominalToken("kotlin.String"), &thrown)
        #expect(thrown != 0)
        #expect(kk_op_is(thrown, nominalToken("kotlin.ClassCastException")) == 1)
    }

    @Test
    func scopeBoxFollowsRegisteredSupertypeEdges() {
        let scopeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.DeepRecursiveScope")
        runtimeRegisterTypeEdge(
            childTypeID: scopeTypeID,
            parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.Any")
        )
        let scope = registerRuntimeObject(
            RuntimeDeepRecursiveScopeBox(function: makeFunctionBox()) as AnyObject
        )
        #expect(kk_op_is(scope, nominalToken("kotlin.Any")) == 1)
    }

    @Test
    func functionBoxAnswersDeepRecursiveFunctionChecks() {
        let raw = registerRuntimeObject(makeFunctionBox() as AnyObject)
        let functionToken = nominalToken("kotlin.DeepRecursiveFunction")
        #expect(kk_op_is(raw, functionToken) == 1)
        #expect(kk_op_is(raw, nominalToken("kotlin.DeepRecursiveScope")) == 0)
        var thrown = 0
        #expect(kk_op_cast(raw, functionToken, &thrown) == raw)
        #expect(thrown == 0)
    }
}

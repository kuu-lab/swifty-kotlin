#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func importedComposeGetterRecognizesComposerAndChangeMask() throws {
        let method = JVMForeignMethod(
            owner: "fixture/InsetsKt", name: "getInset",
            descriptor: "(Lfixture/Insets;Landroidx/compose/runtime/Composer;I)I",
            parameters: [.reference("fixture/Insets", nullable: false),
                         .reference("androidx/compose/runtime/Composer", nullable: false), .int],
            result: .int, isStatic: true, isInterface: false, isAbstract: false,
            annotations: [JVMAnnotation(descriptor: "Landroidx/compose/runtime/Composable;", visible: false)]
        )
        #expect(method.composePropertyABI(hasReceiver: true))
        #expect(!method.composePropertyABI(hasReceiver: false))
        var ordinary = method
        ordinary.annotations = []
        #expect(!ordinary.composePropertyABI(hasReceiver: true))
    }
}
#endif

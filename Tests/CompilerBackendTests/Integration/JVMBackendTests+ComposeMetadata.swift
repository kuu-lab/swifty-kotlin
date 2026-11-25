#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func composeMetadataRequiresTheAnnotatedClassfileEntryPoint() {
        let parameters: [JVMValueType] = [.int, JVMCompose.composerType, .int, .int]
        let descriptor = "(ILandroidx/compose/runtime/Composer;II)V"
        let function = JVMKotlinFunction(
            name: "Content", jvmName: nil, descriptor: descriptor, result: "kotlin.Unit",
            parameters: [.init(name: "size", sourceType: "kotlin.Int", isVararg: false, hasDefaultValue: true)],
            typeParameters: [], contextParameters: [], receiver: nil, isSuspend: false
        )
        var method = JVMForeignMethod(
            owner: "sample/ContentKt", name: "Content", descriptor: descriptor,
            parameters: parameters, result: .unit, isStatic: true, isInterface: false, isAbstract: false
        )
        #expect(method.composeABI(for: function) == nil)
        method.annotations = [JVMAnnotation(descriptor: "Landroidx/compose/runtime/Composable;", visible: false)]
        #expect(method.composeABI(for: function)?.changes == 1)
        #expect(method.composeABI(for: function)?.defaults == 1)
    }

    @Test
    func composeCompanionExtensionPropertyGetterAcceptsHiddenComposerABI() {
        let companion = JVMValueType.reference("androidx/compose/foundation/layout/WindowInsets$Companion", nullable: false)
        let insets = JVMValueType.reference("androidx/compose/foundation/layout/WindowInsets", nullable: false)
        let descriptor = "(Landroidx/compose/foundation/layout/WindowInsets$Companion;Landroidx/compose/runtime/Composer;I)Landroidx/compose/foundation/layout/WindowInsets;"
        let property = JVMKotlinTopLevelProperty(
            name: "statusBars",
            receiver: "androidx.compose.foundation.layout.WindowInsets.Companion",
            result: "androidx.compose.foundation.layout.WindowInsets",
            getterName: "getStatusBars",
            getterDescriptor: descriptor
        )
        let composable = [JVMAnnotation(descriptor: "Landroidx/compose/runtime/Composable;", visible: false)]

        func getter(_ parameters: [JVMValueType], annotations: [JVMAnnotation]) -> JVMForeignMethod {
            var method = JVMForeignMethod(
                owner: "androidx/compose/foundation/layout/WindowInsets_androidKt",
                name: "getStatusBars",
                descriptor: descriptor,
                parameters: parameters,
                result: insets,
                isStatic: true,
                isInterface: false,
                isAbstract: false
            )
            method.annotations = annotations
            return method
        }

        #expect(JVMClassReader.matchesTopLevelPropertyGetter(
            getter([companion, JVMCompose.composerType, .int], annotations: composable),
            property: property
        ))
        #expect(!JVMClassReader.matchesTopLevelPropertyGetter(
            getter([companion, JVMCompose.composerType, .int], annotations: []),
            property: property
        ))
        #expect(!JVMClassReader.matchesTopLevelPropertyGetter(
            getter([companion, JVMCompose.composerType, .long], annotations: composable),
            property: property
        ))
    }
}
#endif

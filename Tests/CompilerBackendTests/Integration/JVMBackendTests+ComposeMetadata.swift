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
}
#endif

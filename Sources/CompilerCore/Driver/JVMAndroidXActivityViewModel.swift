import Foundation

enum JVMAndroidXActivityViewModel {
    static let facade = "androidx/activity/ActivityViewModelLazyKt"
    static let activity = "androidx/activity/ComponentActivity"
    static let storeProducer = facade + "$viewModels$1"
    static let defaultFactoryProducer = facade + "$viewModels$factoryPromise$1"
    static let lazyModel = "androidx/lifecycle/ViewModelLazy"
    static let function = "kotlin/jvm/functions/Function0"
    static let kClass = "kotlin/reflect/KClass"

    static func isEntry(owner: String, name: String, descriptor: String) -> Bool {
        owner == facade && name == "viewModels"
            && descriptor == "(L\(activity);L\(function);)Lkotlin/Lazy;"
    }
}

extension JVMClasspathIndex {
    func injectActivityViewModel(into ctx: CompilationContext) {
        typealias ViewModel = JVMAndroidXActivityViewModel
        let producerConstructor = "(L\(ViewModel.activity);)V"
        guard let facade = classes[ViewModel.facade], facade.isKotlinFileFacade == true,
              facade.methods.contains(where: {
                  $0.isStatic && ViewModel.isEntry(owner: $0.owner, name: $0.name, descriptor: $0.descriptor)
              }),
              hasPublicConstructor(ViewModel.storeProducer, descriptor: producerConstructor),
              hasPublicConstructor(ViewModel.defaultFactoryProducer, descriptor: producerConstructor),
              hasPublicConstructor(ViewModel.lazyModel, descriptor: "(L\(ViewModel.kClass);L\(ViewModel.function);L\(ViewModel.function);)V")
        else { return }
        let source = """
        package androidx.activity
        inline fun <reified VM : androidx.lifecycle.ViewModel> ComponentActivity.viewModels(
            noinline factoryProducer: (() -> androidx.lifecycle.ViewModelProvider.Factory)? = null
        ): kotlin.Lazy<VM> = null!!
        """
        activityViewModelFile = ctx.sourceManager.addFile(
            path: "<kswiftk-jvm-import>/androidx-activity-view-model.kt",
            contents: Data(source.utf8), origin: .residualStdlib
        )
    }
}

extension JVMFunctionBuilder {
    func importedActivityViewModel(
        _ binding: CallBinding, args: [CallArgument], receiver: ExprID?, receiverValue: JVMValue?, id: ExprID
    ) throws -> JVMIntrinsicResult? {
        guard let file = context.jvmImports?.activityViewModelFile,
              program.sema.symbols.symbol(binding.chosenCallee)?.declSite?.start.file == file else { return nil }
        guard let activity = try receiverValue ?? receiver.map(requireValue) ?? implicitExtensionReceiver(id),
              let model = binding.substitutedTypeArguments.first
        else { throw fail("viewModels requires a ComponentActivity and a reified ViewModel type.", id) }

        typealias ViewModel = JVMAndroidXActivityViewModel
        let activityType = JVMValueType.reference(ViewModel.activity, nullable: false)
        let function = JVMValueType.reference(ViewModel.function, nullable: true)
        let activityArgument = try convert(activity, to: activityType)
        let factory = try value(function)
        let selected = label()
        if let argument = args.first {
            let provided = try convert(requireValue(argument.expr), to: function)
            let missing = try value(.boolean)
            instructions.append(.copy(provided, factory))
            instructions.append(.referenceCompare(.equal, provided, try zero(function), missing))
            instructions.append(.jumpIfFalse(missing, selected))
        }
        let fallback = try constructJDK(ViewModel.defaultFactoryProducer, parameters: [activityType], arguments: [activityArgument])
        instructions.append(.copy(try convert(fallback, to: function), factory))
        mark(selected)

        let token = try materializeReifiedToken(model).klass
        let kClass = JVMValueType.reference(ViewModel.kClass, nullable: false)
        guard let modelClass = try jdkCall("kotlin/jvm/internal/Reflection", "getOrCreateKotlinClass",
                                           [token.type], kClass, arguments: [token])
        else { throw fail("Missing JVM ViewModel class token.", id) }
        let store = try constructJDK(ViewModel.storeProducer, parameters: [activityType], arguments: [activityArgument])
        let lazy = try constructJDK(ViewModel.lazyModel, parameters: [kClass, function, function],
                                    arguments: [modelClass, convert(store, to: function), factory])
        return JVMIntrinsicResult(value: try convert(lazy, to: .reference("kotlin/Lazy", nullable: false)))
    }
}

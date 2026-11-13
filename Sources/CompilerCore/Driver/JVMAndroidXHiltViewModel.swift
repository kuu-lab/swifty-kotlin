import Foundation

extension JVMClasspathIndex {
    private static let hiltFacade = "androidx/hilt/navigation/compose/HiltViewModelKt"
    private static let viewModelFacade = "androidx/lifecycle/viewmodel/compose/ViewModelKt"
    private static let localOwner = "androidx/lifecycle/viewmodel/compose/LocalViewModelStoreOwner"
    private static let storeOwner = "Landroidx/lifecycle/ViewModelStoreOwner;"
    private static let factory = "Landroidx/lifecycle/ViewModelProvider$Factory;"
    private static let model = "Landroidx/lifecycle/ViewModel;"
    private static let extras = "Landroidx/lifecycle/viewmodel/CreationExtras;"
    private static let composerType = "Landroidx/compose/runtime/Composer;"

    static func isReifiedHiltViewModel(owner: String, name: String, descriptor: String) -> Bool {
        owner == hiltFacade && name == "hiltViewModel"
            && descriptor == "(\(storeOwner)\(composerType)II)\(model)"
    }

    private func hiltEntry(_ owner: String, _ name: String, _ descriptor: String, staticMember: Bool = true) -> JVMForeignMethod? {
        classes[owner]?.methods.first {
            $0.name == name && $0.descriptor == descriptor && $0.isStatic == staticMember && !$0.isProtected
        }
    }

    var hiltViewModelMethods: (owner: JVMForeignMethod, factory: JVMForeignMethod, model: JVMForeignMethod)? {
        guard hasComposeRuntime,
              classes[Self.hiltFacade]?.isKotlinFileFacade == true,
              hiltEntry(Self.hiltFacade, "hiltViewModel", "(\(Self.storeOwner)\(Self.composerType)II)\(Self.model)") != nil,
              let owner = hiltEntry(Self.localOwner, "getCurrent", "(\(Self.composerType)I)\(Self.storeOwner)", staticMember: false),
              let factory = hiltEntry(Self.hiltFacade, "createHiltViewModelFactory", "(\(Self.storeOwner)\(Self.composerType)I)\(Self.factory)"),
              let model = hiltEntry(Self.viewModelFacade, "viewModel", "(Ljava/lang/Class;\(Self.storeOwner)Ljava/lang/String;\(Self.factory)\(Self.extras)\(Self.composerType)II)\(Self.model)")
        else { return nil }
        return (owner, factory, model)
    }

    func injectHiltViewModel(into ctx: CompilationContext) {
        guard hiltViewModelMethods != nil else { return }
        let source = """
        package androidx.hilt.navigation.compose
        @androidx.compose.runtime.Composable
        inline fun <reified VM : androidx.lifecycle.ViewModel> hiltViewModel(
            viewModelStoreOwner: androidx.lifecycle.ViewModelStoreOwner = null!!
        ): VM = null!!
        """
        hiltViewModelFile = ctx.sourceManager.addFile(
            path: "<kswiftk-jvm-import>/androidx-hilt-view-model.kt",
            contents: Data(source.utf8), origin: .residualStdlib
        )
    }
}

extension JVMFunctionBuilder {
    func importedHiltViewModel(
        _ binding: CallBinding, args: [CallArgument], expectedResult: JVMValueType?, id: ExprID
    ) throws -> JVMIntrinsicResult? {
        guard let imports = context.jvmImports, let file = imports.hiltViewModelFile,
              program.sema.symbols.symbol(binding.chosenCallee)?.declSite?.start.file == file,
              let methods = imports.hiltViewModelMethods else { return nil }
        guard let composer = activeComposer, let type = binding.substitutedTypeArguments.first else {
            throw fail("hiltViewModel requires an active Composer and reified ViewModel type.", id)
        }
        let unchanged = try constant(.int(0), .int)
        let owner: JVMValue
        if let argument = args.first {
            owner = try requireValue(argument.expr)
        } else {
            let receiver = try value(.reference(methods.owner.owner, nullable: false))
            instructions.append(.getStatic(JVMField(owner: methods.owner.owner, name: "INSTANCE", type: receiver.type, access: 0x0019), receiver))
            let result = try jdkCall(methods.owner.owner, methods.owner.name, methods.owner.parameters,
                                     methods.owner.result, receiver: receiver, arguments: [composer, unchanged])!
            let present = label()
            let missing = try value(.boolean)
            instructions.append(.referenceCompare(.equal, result, try zero(result.type), missing))
            instructions.append(.jumpIfFalse(missing, present))
            let message = try constant(.string("No ViewModelStoreOwner was provided via LocalViewModelStoreOwner"), .string)
            instructions.append(.throwValue(try constructJDK("java/lang/IllegalStateException", parameters: [.string], arguments: [message])))
            mark(present)
            owner = result
        }
        let factory = try jdkCall(methods.factory.owner, methods.factory.name, methods.factory.parameters,
                                  methods.factory.result, arguments: [owner, composer, unchanged])!
        let token = try materializeReifiedToken(type).klass
        let key = try zero(methods.model.parameters[2])
        let extras = try zero(methods.model.parameters[4])
        // The fifth source parameter defaults to the owner's CreationExtras.
        let defaults = try constant(.int(1 << 4), .int)
        let result = try jdkCall(methods.model.owner, methods.model.name, methods.model.parameters, methods.model.result,
                                 arguments: [token, owner, key, factory, extras, composer, unchanged, defaults],
                                 resolved: expectedResult ?? program.expressionType(id))
        return JVMIntrinsicResult(value: result)
    }
}

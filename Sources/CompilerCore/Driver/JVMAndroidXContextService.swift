import Foundation

enum JVMAndroidXContextService {
    static let facade = "androidx/core/content/ContextKt"
    static let compat = "androidx/core/content/ContextCompat"
    static let name = "getSystemService"

    static func isEntry(owner: String, name: String, descriptor: String) -> Bool {
        owner == facade && name == Self.name && descriptor == "(Landroid/content/Context;)Ljava/lang/Object;"
    }

    static func isEntry(_ method: JVMForeignMethod) -> Bool {
        method.isStatic && isEntry(owner: method.owner, name: method.name, descriptor: method.descriptor)
    }
}

extension JVMClasspathIndex {
    var contextServiceMethod: JVMForeignMethod? {
        guard classes[JVMAndroidXContextService.facade]?.isKotlinFileFacade == true,
              classes[JVMAndroidXContextService.facade]?.methods.contains(where: JVMAndroidXContextService.isEntry) == true,
              classes["android/content/Context"] != nil else { return nil }
        return classes[JVMAndroidXContextService.compat]?.methods.first {
            $0.isStatic && !$0.isProtected && $0.name == JVMAndroidXContextService.name
                && $0.descriptor == "(Landroid/content/Context;Ljava/lang/Class;)Ljava/lang/Object;"
        }
    }

    func injectContextService(into ctx: CompilationContext) {
        guard contextServiceMethod != nil else { return }
        let source = """
        package androidx.core.content
        inline fun <reified T : Any> android.content.Context.getSystemService(): T? = null
        """
        contextServiceFile = ctx.sourceManager.addFile(
            path: "<kswiftk-jvm-import>/androidx-context-service.kt",
            contents: Data(source.utf8), origin: .residualStdlib
        )
    }
}

extension JVMFunctionBuilder {
    func importedContextService(
        _ binding: CallBinding, receiver: ExprID?, receiverValue: JVMValue?, id: ExprID
    ) throws -> JVMIntrinsicResult? {
        guard let imports = context.jvmImports, let file = imports.contextServiceFile,
              program.sema.symbols.symbol(binding.chosenCallee)?.declSite?.start.file == file,
              let method = imports.contextServiceMethod else { return nil }
        guard let receiver = try receiverValue ?? receiver.map(requireValue) ?? implicitExtensionReceiver(id) else {
            throw fail("Missing JVM context receiver for getSystemService.", id)
        }
        guard let type = binding.substitutedTypeArguments.first else {
            throw fail("getSystemService requires a reified service type.", id)
        }
        let token = try materializeReifiedToken(type).klass
        return JVMIntrinsicResult(value: try jdkCall(
            method.owner, method.name, method.parameters, method.result, arguments: [receiver, token],
            resolved: program.expressionType(id)
        ))
    }
}

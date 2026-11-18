import Foundation

extension JVMForeignMethod {
    var isReifiedWorkBuilder: Bool {
        owner == "androidx/work/OneTimeWorkRequestKt" && isStatic && name == "OneTimeWorkRequestBuilder"
            && descriptor == "()Landroidx/work/OneTimeWorkRequest$Builder;"
    }
}

extension JVMClasspathIndex {
    var oneTimeWorkRequestConstructor: JVMForeignMethod? {
        guard classes["androidx/work/OneTimeWorkRequestKt"]?.methods.contains(where: \.isReifiedWorkBuilder) == true,
              let builder = classes["androidx/work/OneTimeWorkRequest$Builder"] else { return nil }
        return builder.methods.first {
            $0.isConstructor && !$0.isProtected && $0.descriptor == "(Ljava/lang/Class;)V"
        }
    }

    func injectOneTimeWorkRequestBuilder(into ctx: CompilationContext) {
        guard oneTimeWorkRequestConstructor != nil else { return }
        let source = """
        package androidx.work
        inline fun <reified W : androidx.work.ListenableWorker> OneTimeWorkRequestBuilder(): androidx.work.OneTimeWorkRequest.Builder = null!!
        """
        oneTimeWorkRequestBuilderFile = ctx.sourceManager.addFile(
            path: "<kswiftk-jvm-import>/workmanager-builder.kt",
            contents: Data(source.utf8), origin: .residualStdlib
        )
    }
}

extension JVMFunctionBuilder {
    func importedOneTimeWorkRequestBuilder(_ binding: CallBinding, id: ExprID) throws -> JVMIntrinsicResult? {
        guard let imports = context.jvmImports, let file = imports.oneTimeWorkRequestBuilderFile,
              program.sema.symbols.symbol(binding.chosenCallee)?.declSite?.start.file == file,
              let constructor = imports.oneTimeWorkRequestConstructor else { return nil }
        guard let type = binding.substitutedTypeArguments.first.map({ program.specialized($0) }),
              case .classType = program.sema.types.kind(of: type) else {
            throw fail("OneTimeWorkRequestBuilder requires a concrete ListenableWorker class.", id)
        }
        let worker = try javaClass(program.classTokenType(type))
        return JVMIntrinsicResult(value: try constructJDK(
            constructor.owner, parameters: constructor.parameters, arguments: [worker]
        ))
    }
}

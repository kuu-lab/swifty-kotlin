import Foundation

extension JVMForeignMethod {
    var isReifiedGlanceAction: Bool {
        owner == "androidx/glance/action/StartActivityActionKt" && isStatic && name == "actionStartActivity"
            && descriptor == "(Landroidx/glance/action/ActionParameters;)Landroidx/glance/action/Action;"
    }
}

extension JVMClasspathIndex {
    private static let glanceFacade = "androidx/glance/action/StartActivityActionKt"
    private static let glanceAction = "Landroidx/glance/action/Action;"
    private static let glanceParameters = "Landroidx/glance/action/ActionParameters;"

    var glanceActivityAction: (ordinary: JVMForeignMethod, defaults: JVMForeignMethod)? {
        guard let facade = classes[Self.glanceFacade],
              facade.methods.contains(where: \.isReifiedGlanceAction),
              let ordinary = facade.methods.first(where: {
                  $0.isStatic && $0.name == "actionStartActivity"
                      && $0.descriptor == "(Ljava/lang/Class;" + Self.glanceParameters + ")" + Self.glanceAction
              }),
              let defaults = facade.defaultArgumentMethods.first(where: {
                  $0.name == "actionStartActivity$default"
                      && $0.descriptor == "(Ljava/lang/Class;" + Self.glanceParameters + "ILjava/lang/Object;)" + Self.glanceAction
              })
        else { return nil }
        return (ordinary, defaults)
    }

    func injectGlanceActivityAction(into ctx: CompilationContext) {
        guard glanceActivityAction != nil else { return }
        let source = """
        package androidx.glance.action
        inline fun <reified T : android.app.Activity> actionStartActivity(
            parameters: androidx.glance.action.ActionParameters = null!!
        ): androidx.glance.action.Action = null!!
        """
        glanceActivityFile = ctx.sourceManager.addFile(
            path: "<kswiftk-jvm-import>/glance-start-activity.kt",
            contents: Data(source.utf8), origin: .residualStdlib
        )
    }
}

extension JVMFunctionBuilder {
    func importedGlanceActivityAction(
        _ binding: CallBinding, args: [CallArgument], id: ExprID
    ) throws -> JVMIntrinsicResult? {
        guard let imports = context.jvmImports, let file = imports.glanceActivityFile,
              program.sema.symbols.symbol(binding.chosenCallee)?.declSite?.start.file == file,
              let action = imports.glanceActivityAction else { return nil }
        guard let type = binding.substitutedTypeArguments.first.map({ program.specialized($0) }),
              case .classType = program.sema.types.kind(of: type) else {
            throw fail("Glance actionStartActivity requires a concrete Activity class.", id)
        }
        let activity = try javaClass(program.classTokenType(type))
        if let parameters = args.first {
            return JVMIntrinsicResult(value: try jdkCall(
                action.ordinary.owner, action.ordinary.name, action.ordinary.parameters, action.ordinary.result,
                arguments: [activity, try requireValue(parameters.expr)]
            ))
        }
        // The class token occupies the first default-mask slot.
        let omitted = try constant(.int(2), .int)
        let parameters = try zero(action.defaults.parameters[1])
        let marker = try zero(action.defaults.parameters[3])
        return JVMIntrinsicResult(value: try jdkCall(
            action.defaults.owner, action.defaults.name, action.defaults.parameters, action.defaults.result,
            arguments: [activity, parameters, omitted, marker]
        ))
    }
}

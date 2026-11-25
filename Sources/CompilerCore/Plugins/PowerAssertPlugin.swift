struct PowerAssertPlugin: CompilerPlugin {
    let id = "org.jetbrains.kotlin.powerassert"

    func applySemaTransform(_ context: CompilerPluginSemaContext) {
        let functions = context.pluginConfig.optionValues(for: id, key: "function")
        guard !functions.isEmpty else { return }
        context.sema.powerAssertFunctions.formUnion(functions)
    }
}

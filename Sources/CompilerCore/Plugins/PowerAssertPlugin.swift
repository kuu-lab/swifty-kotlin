/// kotlinc `kotlin-power-assert` equivalent.
/// Rewrites calls to configured assertion functions (e.g. `kotlin.assert`)
/// lacking a message lambda into calls that render a rich source diagram
/// showing intermediate expression values when the assertion fails.
///
/// Configuration (repeatable):
///   -P plugin:org.jetbrains.kotlin.powerassert:function=<fqName>
struct PowerAssertPlugin: CompilerPlugin {
    let id = "org.jetbrains.kotlin.powerassert"

    func applySemaTransform(_ context: CompilerPluginSemaContext) {
        let functions = context.pluginConfig.optionValues(for: id, key: "function")
        guard !functions.isEmpty else { return }
        context.sema.powerAssertFunctions.formUnion(functions)
    }
}

struct SamWithReceiverPlugin: CompilerPlugin {
    let id = "org.jetbrains.kotlin.samWithReceiver"

    func applySemaTransform(_ context: CompilerPluginSemaContext) {
        let triggers = Set(context.pluginConfig.optionValues(for: id, key: "annotation"))
        guard !triggers.isEmpty else { return }

        let symbols = context.symbols
        for symbol in symbols.allSymbols() {
            guard symbol.kind == .interface,
                  symbol.flags.contains(.funInterface),
                  !symbol.flags.contains(.synthetic),
                  !symbol.flags.contains(.precomputedStdlibSynthetic),
                  symbols.annotations(for: symbol.id).contains(where: { triggers.contains($0.annotationFQName) })
            else { continue }
            context.sema.samWithReceiverInterfaces.insert(symbol.id)
        }
    }
}

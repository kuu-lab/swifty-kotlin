/// kotlinc `kotlin-sam-with-receiver` equivalent.
/// Functional (`fun interface`) interfaces annotated with a configured annotation
/// have the first parameter of their single abstract method converted into the
/// implicit receiver (`this`) of SAM lambda conversions.
///
/// Configuration (repeatable):
///   -P plugin:org.jetbrains.kotlin.samWithReceiver:annotation=<fqName>
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

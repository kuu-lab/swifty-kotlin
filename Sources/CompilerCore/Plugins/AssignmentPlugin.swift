/// kotlinc `kotlin-assignment` equivalent.
/// Types or properties annotated with a configured annotation allow `val` or
/// type-mismatched assignments `lhs = rhs` to be rewritten into `lhs.assign(rhs)`.
///
/// Configuration (repeatable):
///   -P plugin:org.jetbrains.kotlin.assignment:annotation=<fqName>
struct AssignmentPlugin: CompilerPlugin {
    let id = "org.jetbrains.kotlin.assignment"

    func applySemaTransform(_ context: CompilerPluginSemaContext) {
        let triggers = Set(context.pluginConfig.optionValues(for: id, key: "annotation"))
        guard !triggers.isEmpty else { return }

        let symbols = context.symbols
        for symbol in symbols.allSymbols() {
            guard !symbol.flags.contains(.synthetic),
                  !symbol.flags.contains(.precomputedStdlibSynthetic),
                  symbols.annotations(for: symbol.id).contains(where: { triggers.contains($0.annotationFQName) })
            else { continue }

            switch symbol.kind {
            case .class, .interface, .object, .enumClass:
                context.sema.assignmentOverloadTypes.insert(symbol.id)
            case .property, .field:
                context.sema.assignmentOverloadProperties.insert(symbol.id)
            default:
                break
            }
        }
    }
}

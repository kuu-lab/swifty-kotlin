/// kotlinc `kotlin-allopen` equivalent. Classes annotated with a configured
/// annotation become `open`, and their directly declared members become
/// overridable, before inheritance/override validation runs.
///
/// Configuration (repeatable):
///   -P plugin:org.jetbrains.kotlin.allopen:annotation=<fqName>
///
/// The plugin only transforms source declarations in the current module;
/// imported symbols keep their recorded modality.
struct AllOpenPlugin: CompilerPlugin {
    let id = "org.jetbrains.kotlin.allopen"

    func applySemaTransform(_ context: CompilerPluginSemaContext) {
        let triggers = Set(context.pluginConfig.optionValues(for: id, key: "annotation"))
        guard !triggers.isEmpty else { return }
        let symbols = context.symbols
        for symbol in symbols.allSymbols() {
            guard symbol.kind == .class,
                  !symbol.flags.contains(.importedLibrary),
                  !symbol.flags.contains(.synthetic),
                  !symbol.flags.contains(.precomputedStdlibSynthetic),
                  hasTriggerAnnotation(symbol.id, triggers: triggers, symbols: symbols)
            else { continue }
            applyAllOpen(to: symbol.id, symbols: symbols)
        }
    }

    private func hasTriggerAnnotation(
        _ symbolID: SymbolID,
        triggers: Set<String>,
        symbols: SymbolTable
    ) -> Bool {
        symbols.annotations(for: symbolID).contains { triggers.contains($0.annotationFQName) }
    }

    private func applyAllOpen(to classID: SymbolID, symbols: SymbolTable) {
        symbols.insertFlags(.openType, for: classID)
        for memberID in symbols.declaredChildren(of: classID) {
            guard let member = symbols.symbol(memberID),
                  isOpenableMemberKind(member.kind),
                  member.visibility != .private,
                  !member.flags.contains(.finalMember),
                  !member.flags.contains(.synthetic),
                  !member.flags.contains(.importedLibrary)
            else { continue }
            symbols.insertFlags(.openType, for: memberID)
        }
    }

    /// Kinds a member can take `open` on. Objects, enums, interfaces,
    /// annotation classes, constructors and non-callable members cannot be
    /// opened; nested plain classes can.
    private func isOpenableMemberKind(_ kind: SymbolKind) -> Bool {
        switch kind {
        case .function, .property, .class:
            return true
        default:
            return false
        }
    }
}

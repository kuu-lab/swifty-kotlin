/// Lazily-resolved imported inline function bodies.
///
/// Library import registers one `Descriptor` per imported inline symbol —
/// the resolved inline-KIR path plus the metadata a later parse needs —
/// instead of reading and KIR-parsing every artifact eagerly. The body is
/// read, parsed, and materialized into the consumer arena the first time an
/// expansion actually asks for it (`function(for:arena:)`); bodies that no
/// call site ever expands stay unparsed.
///
/// A descriptor whose parse fails is dropped and remembered in
/// `failedSymbols`, matching the eager behavior where a failed import simply
/// never entered the table: the symbol is no longer treated as an expansion
/// target or a bodyless callee.
public final class ImportedInlineFunctionStore {
    /// Everything needed to restore one imported inline body on demand.
    public struct Descriptor {
        /// Path to the library's inline-KIR artifact, already resolved and
        /// validated to live under the library's `inlineKIRDir`.
        public let path: String
        /// The signature captured when the binding was applied; parameter
        /// and return types are rebuilt from it at parse time.
        public let signature: FunctionSignature?
        /// The declared name of the function (the producer's
        /// `KIRFunction.name`, which `nameB64` serializes). Used by the
        /// by-name expansion fallback without parsing the body.
        public let name: InternedString

        public init(path: String, signature: FunctionSignature?, name: InternedString) {
            self.path = path
            self.signature = signature
            self.name = name
        }
    }

    /// Deferred bodies keyed by callee symbol.
    public private(set) var descriptors: [SymbolID: Descriptor] = [:]

    /// Bodies that are already usable as expansion targets: bodies seeded
    /// pre-materialized (tests) plus descriptors resolved on demand. Read
    /// `function(for:arena:)` rather than this table to resolve lazily.
    public private(set) var functions: [SymbolID: KIRFunction]

    /// Descriptors whose deferred parse already failed. Keeping them out of
    /// `descriptors` mirrors the eager path, where a failed import left no
    /// entry at all.
    public private(set) var failedSymbols: Set<SymbolID> = []

    /// The state a deferred parse needs, captured once after every imported
    /// binding has been applied so lazy parses see the same callee-resolution
    /// maps the eager parse did.
    private struct ParseContext {
        let types: TypeSystem
        let interner: StringInterner
        let diagnostics: DiagnosticEngine
        let externalLinkNameToSymbol: [String: SymbolID]
        let importedSymbolByFQName: [String: SymbolID]
    }

    private var parseContext: ParseContext?

    public init(functions: [SymbolID: KIRFunction] = [:]) {
        self.functions = functions
    }

    /// Whether no imported inline bodies are known — neither deferred nor
    /// already resolved.
    public var isEmpty: Bool {
        descriptors.isEmpty && functions.isEmpty
    }

    /// Registers a deferred body for `symbol`. A pre-seeded function wins, so
    /// a descriptor never shadows an already-resolved entry.
    func register(_ descriptor: Descriptor, for symbol: SymbolID) {
        guard functions[symbol] == nil else { return }
        descriptors[symbol] = descriptor
    }

    /// Seeds an already-parsed body (used when the lazy metadata loader
    /// resolves a demanded inline callee before the expansion pass).
    func seed(_ function: KIRFunction, for symbol: SymbolID) {
        functions[symbol] = function
        descriptors.removeValue(forKey: symbol)
    }

    subscript(symbol: SymbolID) -> KIRFunction? {
        get { functions[symbol] }
        set {
            if let newValue {
                seed(newValue, for: symbol)
            } else {
                functions.removeValue(forKey: symbol)
                descriptors.removeValue(forKey: symbol)
            }
        }
    }

    /// Captures the resolution context once, after all imported bindings have
    /// been applied. Called by `loadImportedLibrarySymbols` so deferred
    /// parses resolve callees against the final link-name and FQ-name maps.
    func bindParseContext(
        types: TypeSystem,
        interner: StringInterner,
        diagnostics: DiagnosticEngine,
        externalLinkNameToSymbol: [String: SymbolID],
        importedSymbolByFQName: [String: SymbolID]
    ) {
        parseContext = ParseContext(
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            externalLinkNameToSymbol: externalLinkNameToSymbol,
            importedSymbolByFQName: importedSymbolByFQName
        )
    }

    /// The expansion-ready body for `symbol`, resolving its descriptor on
    /// first access: read + parse the artifact, then rebind its expression
    /// IDs into `arena`. Returns `nil` when no body is available — an unknown
    /// symbol, a failed earlier parse, a missing parse context, or a parse
    /// that fails now — the same set of cases that produced no table entry
    /// under eager import.
    func function(for symbol: SymbolID, arena: KIRArena) -> KIRFunction? {
        if let function = functions[symbol] {
            return function
        }
        guard let descriptor = descriptors[symbol] else {
            return nil
        }
        defer { descriptors.removeValue(forKey: symbol) }
        guard let parseContext,
              let parsed = DataFlowSemaPhase.parseImportedInlineFunction(
                  path: descriptor.path,
                  importedSymbol: symbol,
                  signature: descriptor.signature,
                  types: parseContext.types,
                  interner: parseContext.interner,
                  diagnostics: parseContext.diagnostics,
                  externalLinkNameToSymbol: parseContext.externalLinkNameToSymbol,
                  importedSymbolByFQName: parseContext.importedSymbolByFQName
              )
        else {
            failedSymbols.insert(symbol)
            return nil
        }
        let materialized = ImportedInlineKIRMaterializer.materializeOne(
            parsed,
            arena: arena,
            types: parseContext.types,
            interner: parseContext.interner
        )
        functions[symbol] = materialized
        return materialized
    }
}

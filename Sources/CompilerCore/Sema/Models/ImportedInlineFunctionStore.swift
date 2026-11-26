/// Resolves producer link names and imported FQ names to consumer symbols.
///
/// The populated maps answer first; a miss falls through to drain closures
/// that register pending compact-index entries, so a declaration that only
/// became reachable after the import phase still resolves for a late inline
/// body parse.
struct ImportedSymbolResolver {
    private let linkNameLookup: (String) -> SymbolID?
    private let fqNameLookup: (String) -> SymbolID?

    init(
        linkNameLookup: @escaping (String) -> SymbolID?,
        fqNameLookup: @escaping (String) -> SymbolID?
    ) {
        self.linkNameLookup = linkNameLookup
        self.fqNameLookup = fqNameLookup
    }

    init(
        externalLinkNameToSymbol: [String: SymbolID],
        importedSymbolByFQName: [String: SymbolID]
    ) {
        linkNameLookup = { externalLinkNameToSymbol[$0] }
        fqNameLookup = { importedSymbolByFQName[$0] }
    }

    func symbol(forLinkName name: String) -> SymbolID? {
        linkNameLookup(name)
    }

    func symbol(forFQName name: String) -> SymbolID? {
        fqNameLookup(name)
    }
}

public final class ImportedInlineFunctionStore {
    public struct Descriptor {
        public let path: String
        public let signature: FunctionSignature?
        public let name: InternedString
        public let reifiedComponentTokens: Bool
        public let packedValueParameterTypes: [TypeID]?

        public init(path: String, signature: FunctionSignature?, name: InternedString,
                    reifiedComponentTokens: Bool = false, packedValueParameterTypes: [TypeID]? = nil) {
            self.path = path
            self.signature = signature
            self.name = name
            self.reifiedComponentTokens = reifiedComponentTokens
            self.packedValueParameterTypes = packedValueParameterTypes
        }
    }

    public private(set) var descriptors: [SymbolID: Descriptor] = [:]

    public private(set) var functions: [SymbolID: KIRFunction]

    public private(set) var failedSymbols: Set<SymbolID> = []

    /// Imported inline symbols whose `.kir` body is still a deferred binding:
    /// the compact index registered them as pending, but the descriptor is
    /// only installed by the lowering-time demand scan. Queries that run
    /// before that scan (e.g. BuildKIR's function-value materialization)
    /// must treat these symbols as having a body available.
    public private(set) var pendingBodySymbols: Set<SymbolID> = []

    /// The state a deferred parse needs, captured once after every imported
    /// binding has been applied so lazy parses see the same callee-resolution
    /// maps the eager parse did. The resolver keeps reading the import-phase
    /// maps live so symbols registered on demand still resolve.
    private struct ParseContext {
        let types: TypeSystem
        let interner: StringInterner
        let diagnostics: DiagnosticEngine
        let resolver: ImportedSymbolResolver
    }

    private var parseContext: ParseContext?

    public init(functions: [SymbolID: KIRFunction] = [:]) {
        self.functions = functions
    }

    public var isEmpty: Bool {
        descriptors.isEmpty && functions.isEmpty
    }

    func register(_ descriptor: Descriptor, for symbol: SymbolID) {
        guard functions[symbol] == nil else { return }
        descriptors[symbol] = descriptor
    }

    func markPendingBody(for symbol: SymbolID) {
        pendingBodySymbols.insert(symbol)
    }

    func clearPendingBody(for symbol: SymbolID) {
        pendingBodySymbols.remove(symbol)
    }

    func bindParseContext(
        types: TypeSystem,
        interner: StringInterner,
        diagnostics: DiagnosticEngine,
        resolver: ImportedSymbolResolver
    ) {
        parseContext = ParseContext(
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            resolver: resolver
        )
    }

    /// Drops a materialized body from the expansion tables. The wasm
    /// backend emits such bodies as ordinary module functions and calls
    /// them directly, so the symbol must stop counting as a bodyless
    /// callee that every call site has to expand.
    func removeMaterializedFunction(for symbol: SymbolID) {
        functions.removeValue(forKey: symbol)
        descriptors.removeValue(forKey: symbol)
        pendingBodySymbols.remove(symbol)
    }

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
                  resolver: parseContext.resolver,
                  reifiedComponentTokens: descriptor.reifiedComponentTokens,
                  packedValueParameterTypes: descriptor.packedValueParameterTypes
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

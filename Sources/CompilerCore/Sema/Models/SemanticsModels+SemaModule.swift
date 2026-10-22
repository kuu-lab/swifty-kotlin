public final class SemaModule {
    var independentBodyCount = 0

    /// KUU-2813: top-level functions proven unreferenced from the entry point
    /// (see `TopLevelFunctionReachability`). Only populated under the opt-in
    /// `reachability-sema` frontend flag; their bodies are neither type
    /// checked nor lowered.
    var unreachableTopLevelFunctionDecls: Set<DeclID> = []

    /// The JVM emitter needs resolved source declarations, including default and
    /// inline parameter information, rather than Native collection shortcuts.
    var requiresResolvedLibraryCalls = false
    /// The trusted JVM runtime owns the implementation of restricted suspension.
    var isJVMStdlibBuild = false

    public let symbols: SymbolTable
    public let types: TypeSystem
    public let bindings: BindingTable
    public let diagnostics: DiagnosticEngine
    public let nameBasedDestructuringMode: NameBasedDestructuringMode
    /// Kept optional for lightweight unit-test sema modules that do not build
    /// a full source environment.
    public let interner: StringInterner?
    /// Imported inline bodies, resolved lazily: library import registers
    /// descriptors (path + signature + name) per symbol, and the inline
    /// lowering pass reads + parses each body on first expansion instead of
    /// paying for every artifact up front.
    public var importedInlineFunctions: ImportedInlineFunctionStore
    /// `.klib` modules whose declarations were imported through
    /// `loadImportedLibrarySymbols`. The decoded IR and the
    /// `(fileIndex, signatureIndex) → SymbolID` map stay alive here so KIR
    /// lowering can materialize serialized bodies into this compilation's
    /// arena (they are `internal` because `LoadedKlibModule` is a
    /// `DataFlowSemaPhase` detail type).
    var klibModules: [DataFlowSemaPhase.LoadedKlibModule] = []
    /// ARCH-029: resolves deferred imported inline bodies that the module's
    /// call sites actually demand. Set by the lazy metadata loader when a v2
    /// `.kklib` index is in use; `nil` on the eager import path.
    public var resolveDemandedImportedInlineBodies: ((KIRModule) -> Void)?
    /// KSP-499 Stage 3: the bundled/user declaration index built once per
    /// compilation (see `DataFlowSemaPhase.run`). Kept here — rather than only
    /// in the transient `BundledSyntheticStubRegistration` thread-local, which
    /// is cleared once header registration finishes — so later phases (body
    /// type-checking, KIR lowering) can still ask "does a real declaration
    /// exist for this (owner, name, arity)?" before applying a hard-coded
    /// compiler intrinsic special-case (e.g. the Flow operator dispatch in
    /// CallTypeChecker+MemberCallInferenceCollectionFlow.swift and
    /// CallLowerer+MemberCalls.swift).
    var bundledIndex: BundledDeclarationIndex
    var wellKnownSymbols: WellKnownSymbols
    /// Import-alias spellings (`import kotlin.enumValueOf as evo` → `evo`)
    /// that bind one of the enum intrinsic FQ names, computed lazily per file
    /// by `enumStdlibSpecialCallKind`. Its callee-name guard must admit every
    /// spelling that can resolve to an intrinsic — an alias binds the same
    /// SymbolID — while keeping the common case O(1).
    var enumIntrinsicAliasNamesByFile: [FileID: Set<InternedString>] = [:]

    public init(
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner? = nil,
        nameBasedDestructuringMode: NameBasedDestructuringMode = .disabled,
        importedInlineFunctions: ImportedInlineFunctionStore = ImportedInlineFunctionStore()
    ) {
        self.symbols = symbols
        self.types = types
        self.bindings = bindings
        self.diagnostics = diagnostics
        self.nameBasedDestructuringMode = nameBasedDestructuringMode
        self.interner = interner
        self.importedInlineFunctions = importedInlineFunctions
        self.bundledIndex = .empty
        self.wellKnownSymbols = .empty
    }

    /// Not `public` because `BundledDeclarationIndex` itself is internal to
    /// CompilerCore; callers outside the module get the public initializer
    /// above, which defaults `bundledIndex` to `.empty`.
    init(
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner? = nil,
        importedInlineFunctions: ImportedInlineFunctionStore = ImportedInlineFunctionStore(),
        nameBasedDestructuringMode: NameBasedDestructuringMode = .disabled,
        bundledIndex: BundledDeclarationIndex
    ) {
        self.symbols = symbols
        self.types = types
        self.bindings = bindings
        self.diagnostics = diagnostics
        self.nameBasedDestructuringMode = nameBasedDestructuringMode
        self.interner = interner
        self.importedInlineFunctions = importedInlineFunctions
        self.bundledIndex = bundledIndex
        self.wellKnownSymbols = .empty
    }
}

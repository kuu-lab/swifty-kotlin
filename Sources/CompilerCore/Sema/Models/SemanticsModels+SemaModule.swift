struct PluginGeneratedConstructorInfo {
    /// Whether the generated body runs property initializers and `init`
    /// blocks (kotlinc no-arg `invokeInitializers`); when false the
    /// constructor performs only the super-constructor delegation, leaving
    /// fields at their JVM-default values.
    var runsInitializers: Bool
    var propertyParameters: [SymbolID]

    init(runsInitializers: Bool, propertyParameters: [SymbolID] = []) {
        self.runsInitializers = runsInitializers
        self.propertyParameters = propertyParameters
    }
}

public enum LombokSynthesizedMethodKind: Sendable {
    case getter(ownerClass: SymbolID, propertySymbol: SymbolID)
    case setter(ownerClass: SymbolID, propertySymbol: SymbolID, returnsSelf: Bool)
    case with(ownerClass: SymbolID, propertySymbol: SymbolID)
    case toStringMethod(ownerClass: SymbolID, properties: [SymbolID], includeFieldNames: Bool)
    case equalsMethod(ownerClass: SymbolID, properties: [SymbolID])
    case hashCodeMethod(ownerClass: SymbolID, properties: [SymbolID])
    case staticConstructorFactory(targetClass: SymbolID, constructorSymbol: SymbolID)
    case builderFactoryMethod(builderClass: SymbolID, builderConstructor: SymbolID)
    case builderSetter(builderClass: SymbolID, propertySymbol: SymbolID)
    case builderBuildMethod(targetClass: SymbolID, builderClass: SymbolID, fieldPairs: [(builderProp: SymbolID, targetProp: SymbolID)])
}

public struct LombokBuilderClassInfo: Sendable {
    public let targetClassSymbol: SymbolID
    public let builderClassSymbol: SymbolID
    public let constructorSymbol: SymbolID
    public let setterMethods: [SymbolID]
    public let buildMethod: SymbolID
}

public struct LombokClassInfo: Sendable {
    public var methodSymbols: [SymbolID] = []
    public var constructorSymbols: [SymbolID] = []
    public var companionSymbol: SymbolID?
    public var builderInfo: LombokBuilderClassInfo?
    public var logPropertySymbol: SymbolID?
}

public struct ParcelizeClassInfo: Sendable {
    public var describeContentsMethod: SymbolID?
    public var writeToParcelMethod: SymbolID?
    public var properties: [SymbolID]
    public var creatorObjectSymbol: SymbolID?
    public var createFromParcelMethod: SymbolID?
    public var newArrayMethod: SymbolID?
    public var parcelSymbol: SymbolID?

    public init(
        describeContentsMethod: SymbolID? = nil,
        writeToParcelMethod: SymbolID? = nil,
        properties: [SymbolID] = [],
        creatorObjectSymbol: SymbolID? = nil,
        createFromParcelMethod: SymbolID? = nil,
        newArrayMethod: SymbolID? = nil,
        parcelSymbol: SymbolID? = nil
    ) {
        self.describeContentsMethod = describeContentsMethod
        self.writeToParcelMethod = writeToParcelMethod
        self.properties = properties
        self.creatorObjectSymbol = creatorObjectSymbol
        self.createFromParcelMethod = createFromParcelMethod
        self.newArrayMethod = newArrayMethod
        self.parcelSymbol = parcelSymbol
    }
}

public struct SerializationPropertyInfo: Sendable {
    public let symbol: SymbolID
    public let serialName: String

    public init(symbol: SymbolID, serialName: String) {
        self.symbol = symbol
        self.serialName = serialName
    }
}

public struct SerializationClassInfo: Sendable {
    public var companionSerializerMethod: SymbolID?
    public var generatedSerializerClass: SymbolID?
    public var companionObjectSymbol: SymbolID?
    public var serializerConstructor: SymbolID?
    public var descriptorProperty: SymbolID?
    public var descriptorGetter: SymbolID?
    public var serializeMethod: SymbolID?
    public var deserializeMethod: SymbolID?
    public var serializableProperties: [SerializationPropertyInfo]

    public init(
        companionSerializerMethod: SymbolID? = nil,
        generatedSerializerClass: SymbolID? = nil,
        companionObjectSymbol: SymbolID? = nil,
        serializerConstructor: SymbolID? = nil,
        descriptorProperty: SymbolID? = nil,
        descriptorGetter: SymbolID? = nil,
        serializeMethod: SymbolID? = nil,
        deserializeMethod: SymbolID? = nil,
        serializableProperties: [SerializationPropertyInfo] = []
    ) {
        self.companionSerializerMethod = companionSerializerMethod
        self.generatedSerializerClass = generatedSerializerClass
        self.companionObjectSymbol = companionObjectSymbol
        self.serializerConstructor = serializerConstructor
        self.descriptorProperty = descriptorProperty
        self.descriptorGetter = descriptorGetter
        self.serializeMethod = serializeMethod
        self.deserializeMethod = deserializeMethod
        self.serializableProperties = serializableProperties
    }
}

struct PluginOverloadedAssignmentInfo {
    let assignCallee: SymbolID
    let targetType: TypeID
    let targetSymbol: SymbolID?
    let callBinding: CallBinding
}

struct PowerAssertCaptureExpr {
    let exprID: ExprID
    let columnOffset: Int
}

struct PowerAssertCallInfo {
    let originalCallee: SymbolID
    let messageOverloadCallee: SymbolID
    let callLineText: String
    let argExprID: ExprID
    let captureExprs: [PowerAssertCaptureExpr]
}

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
    var isJVMStdlibBuild = false
    var jvmClasspathStubFiles: Set<FileID> = []

    var stdlibProfile: StdlibProfile = .full
    var implicitSignedToUnsignedIntegerConversionEnabled = false

    public let symbols: SymbolTable
    public let types: TypeSystem
    public let bindings: BindingTable
    public let diagnostics: DiagnosticEngine
    public let nameBasedDestructuringMode: NameBasedDestructuringMode
    public let interner: StringInterner?
    public var importedInlineFunctions: ImportedInlineFunctionStore
    var klibModules: [DataFlowSemaPhase.LoadedKlibModule] = []
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

    /// Constructors synthesized by compiler plugins (e.g. the no-arg
    /// plugin), keyed by the generated constructor symbol. KIR lowering
    /// consults this to emit the plugin-specific body — a bare
    /// super-constructor delegation — instead of the source-constructor
    /// path that runs property initializers and `init` blocks.
    var pluginGeneratedConstructors: [SymbolID: PluginGeneratedConstructorInfo] = [:]

    public var parcelizeClasses: [SymbolID: ParcelizeClassInfo] = [:]

    public var serializationClasses: [SymbolID: SerializationClassInfo] = [:]

    public var samWithReceiverInterfaces: Set<SymbolID> = []

    public var assignmentOverloadTypes: Set<SymbolID> = []

    public var assignmentOverloadProperties: Set<SymbolID> = []

    var pluginOverloadedAssignments: [ExprID: PluginOverloadedAssignmentInfo] = [:]

    public var powerAssertFunctions: Set<String> = []

    var powerAssertCalls: [ExprID: PowerAssertCallInfo] = [:]

    public var lombokClasses: [SymbolID: LombokClassInfo] = [:]

    public var lombokMethods: [SymbolID: LombokSynthesizedMethodKind] = [:]

    public var lombokBuilderClasses: [SymbolID: LombokBuilderClassInfo] = [:]

    public var composePluginEnabled: Bool = false
    public var composableFunctions: Set<SymbolID> = []
    public var composableFunctionParameters: Set<SymbolID> = []
    public var composableLambdaExprs: Set<ExprID> = []
    public var disallowComposableCallsParameters: Set<SymbolID> = []
    public var readonlyComposableFunctions: Set<SymbolID> = []
    public var stableAnnotatedSymbols: Set<SymbolID> = []
    public var composeComposerSymbol: SymbolID?
    public var composeComposerType: TypeID?

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

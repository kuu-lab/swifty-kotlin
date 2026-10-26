public struct AnnotationNode: Equatable, Codable {
    public let name: String
    /// Reconstructed Kotlin expressions. Single string literals retain one
    /// delimiter pair; literal concatenations use an escaped regular literal.
    public let arguments: [String]
    public let useSiteTarget: String?
    /// Original constructor tokens retain escapes, backticks and lexical scope.
    public let constructionTokens: [Token]?

    public var usageID: String? {
        constructionTokens?.first.map { "\($0.range.start.file.rawValue):\($0.range.start.offset)" }
    }

    public init(name: String, arguments: [String] = [], useSiteTarget: String? = nil, constructionTokens: [Token]? = nil) {
        self.name = name
        self.arguments = arguments
        self.useSiteTarget = useSiteTarget
        self.constructionTokens = constructionTokens
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.arguments == rhs.arguments && lhs.useSiteTarget == rhs.useSiteTarget
    }
}

public struct ASTFile: Codable {
    public let fileID: FileID
    public let packageFQName: [InternedString]
    public let imports: [ImportDecl]
    public let topLevelDecls: [DeclID]
    public let scriptBody: [ExprID]
    public let annotations: [AnnotationNode]
    public let range: SourceRange?

    public init(
        fileID: FileID,
        packageFQName: [InternedString],
        imports: [ImportDecl],
        topLevelDecls: [DeclID],
        scriptBody: [ExprID],
        annotations: [AnnotationNode] = [],
        range: SourceRange? = nil
    ) {
        self.fileID = fileID
        self.packageFQName = packageFQName
        self.imports = imports
        self.topLevelDecls = topLevelDecls
        self.scriptBody = scriptBody
        self.annotations = annotations
        self.range = range
    }
}

public enum ConstructorDelegationKind: Equatable, Codable {
    case this
    case super_
}

public struct ConstructorDelegationCall: Equatable, Codable {
    public let kind: ConstructorDelegationKind
    public let args: [CallArgument]
    public let range: SourceRange

    public init(kind: ConstructorDelegationKind, args: [CallArgument], range: SourceRange) {
        self.kind = kind
        self.args = args
        self.range = range
    }
}

public struct ConstructorDecl: Codable {
    public let range: SourceRange
    public let modifiers: Modifiers
    public let annotations: [AnnotationNode]
    public let valueParams: [ValueParamDecl]
    public let delegationCall: ConstructorDelegationCall?
    public let body: FunctionBody

    public init(
        range: SourceRange,
        modifiers: Modifiers = [],
        annotations: [AnnotationNode] = [],
        valueParams: [ValueParamDecl] = [],
        delegationCall: ConstructorDelegationCall? = nil,
        body: FunctionBody = .unit
    ) {
        self.range = range
        self.modifiers = modifiers
        self.annotations = annotations
        self.valueParams = valueParams
        self.delegationCall = delegationCall
        self.body = body
    }
}

public struct SuperTypeEntry: Equatable, Codable {
    public let typeRef: TypeRefID
    /// When present, this supertype (must be an interface) is implemented by
    /// delegating to the given expression. Absent for non-delegated supertypes.
    public let delegateExpression: ExprID?
    /// Arguments of the superclass constructor invocation in the class header.
    /// Empty for interfaces and for `Base()`.
    public let constructorArgs: [CallArgument]
    /// True when the source wrote the superclass constructor invocation —
    /// `Base(...)` including `Base()` — rather than a bare `Base` reference.
    /// Kotlin requires the invocation for class supertypes; interfaces and
    /// delegated entries list the bare type.
    public let hasConstructorCallSyntax: Bool
    /// Range of the entry's type portion (`Base` in `Base(x)`); used for
    /// supertype diagnostics.
    public let range: SourceRange?

    public init(
        typeRef: TypeRefID,
        delegateExpression: ExprID? = nil,
        constructorArgs: [CallArgument] = [],
        hasConstructorCallSyntax: Bool = false,
        range: SourceRange? = nil
    ) {
        self.typeRef = typeRef
        self.delegateExpression = delegateExpression
        self.constructorArgs = constructorArgs
        self.hasConstructorCallSyntax = hasConstructorCallSyntax
        self.range = range
    }

    private enum CodingKeys: String, CodingKey {
        case typeRef, delegateExpression, constructorArgs, hasConstructorCallSyntax, range
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        typeRef = try container.decode(TypeRefID.self, forKey: .typeRef)
        delegateExpression = try container.decodeIfPresent(ExprID.self, forKey: .delegateExpression)
        constructorArgs = try container.decodeIfPresent([CallArgument].self, forKey: .constructorArgs) ?? []
        hasConstructorCallSyntax = try container.decodeIfPresent(Bool.self, forKey: .hasConstructorCallSyntax) ?? false
        range = try container.decodeIfPresent(SourceRange.self, forKey: .range)
    }
}

/// Used to guarantee Kotlin's declaration-order execution of property
/// initializers and `init` blocks.
public enum ClassBodyInitMember: Equatable, Codable {
    /// A property initializer; the associated value is the index into
    /// `ClassDecl.memberProperties`.
    case property(Int)
    /// An `init { }` block; the associated value is the index into
    /// `ClassDecl.initBlocks`.
    case initBlock(Int)
}

public struct ClassDecl: Codable {
    public let range: SourceRange
    public let name: InternedString
    public let modifiers: Modifiers
    public let annotations: [AnnotationNode]
    public let isInner: Bool
    public let typeParams: [TypeParamDecl]
    public let primaryConstructorParams: [ValueParamDecl]
    public let primaryConstructorModifiers: Modifiers
    public let primaryConstructorAnnotations: [AnnotationNode]
    /// Distinguishes `class Foo()` (has primary ctor) from `class Foo` (no primary ctor).
    public let hasPrimaryConstructorSyntax: Bool
    public let superTypeEntries: [SuperTypeEntry]
    public let nestedTypeAliases: [TypeAliasDecl]
    public let enumEntries: [EnumEntryDecl]
    public let initBlocks: [FunctionBody]
    /// Kotlin guarantees that these execute top-to-bottom in the order they
    /// appear in the class body (spec.md J7).
    public let classBodyInitOrder: [ClassBodyInitMember]
    public let secondaryConstructors: [ConstructorDecl]
    public let memberFunctions: [DeclID]
    public let memberProperties: [DeclID]
    public let nestedClasses: [DeclID]
    public let nestedObjects: [DeclID]
    public let companionObject: DeclID?

    public init(
        range: SourceRange,
        name: InternedString,
        modifiers: Modifiers,
        annotations: [AnnotationNode] = [],
        isInner: Bool = false,
        typeParams: [TypeParamDecl] = [],
        primaryConstructorParams: [ValueParamDecl] = [],
        primaryConstructorModifiers: Modifiers = [],
        primaryConstructorAnnotations: [AnnotationNode] = [],
        hasPrimaryConstructorSyntax: Bool = false,
        superTypeEntries: [SuperTypeEntry] = [],
        nestedTypeAliases: [TypeAliasDecl] = [],
        enumEntries: [EnumEntryDecl] = [],
        initBlocks: [FunctionBody] = [],
        classBodyInitOrder: [ClassBodyInitMember] = [],
        secondaryConstructors: [ConstructorDecl] = [],
        memberFunctions: [DeclID] = [],
        memberProperties: [DeclID] = [],
        nestedClasses: [DeclID] = [],
        nestedObjects: [DeclID] = [],
        companionObject: DeclID? = nil
    ) {
        self.range = range
        self.name = name
        self.modifiers = modifiers
        self.annotations = annotations
        self.isInner = isInner
        self.typeParams = typeParams
        self.primaryConstructorParams = primaryConstructorParams
        self.primaryConstructorModifiers = primaryConstructorModifiers
        self.primaryConstructorAnnotations = primaryConstructorAnnotations
        self.hasPrimaryConstructorSyntax = hasPrimaryConstructorSyntax
        self.superTypeEntries = superTypeEntries
        self.nestedTypeAliases = nestedTypeAliases
        self.enumEntries = enumEntries
        self.initBlocks = initBlocks
        self.classBodyInitOrder = classBodyInitOrder
        self.secondaryConstructors = secondaryConstructors
        self.memberFunctions = memberFunctions
        self.memberProperties = memberProperties
        self.nestedClasses = nestedClasses
        self.nestedObjects = nestedObjects
        self.companionObject = companionObject
    }
}

public struct InterfaceDecl: Codable {
    public let range: SourceRange
    public let name: InternedString
    public let modifiers: Modifiers
    public let annotations: [AnnotationNode]
    public let isFunInterface: Bool
    public let typeParams: [TypeParamDecl]
    public let superTypes: [TypeRefID]
    public let nestedTypeAliases: [TypeAliasDecl]
    public let memberFunctions: [DeclID]
    public let memberProperties: [DeclID]
    public let nestedClasses: [DeclID]
    public let nestedObjects: [DeclID]
    public let companionObject: DeclID?

    public init(
        range: SourceRange,
        name: InternedString,
        modifiers: Modifiers,
        annotations: [AnnotationNode] = [],
        isFunInterface: Bool = false,
        typeParams: [TypeParamDecl] = [],
        superTypes: [TypeRefID] = [],
        nestedTypeAliases: [TypeAliasDecl] = [],
        memberFunctions: [DeclID] = [],
        memberProperties: [DeclID] = [],
        nestedClasses: [DeclID] = [],
        nestedObjects: [DeclID] = [],
        companionObject: DeclID? = nil
    ) {
        self.range = range
        self.name = name
        self.modifiers = modifiers
        self.annotations = annotations
        self.isFunInterface = isFunInterface
        self.typeParams = typeParams
        self.superTypes = superTypes
        self.nestedTypeAliases = nestedTypeAliases
        self.memberFunctions = memberFunctions
        self.memberProperties = memberProperties
        self.nestedClasses = nestedClasses
        self.nestedObjects = nestedObjects
        self.companionObject = companionObject
    }
}

public struct ObjectDecl: Codable {
    public let range: SourceRange
    public let name: InternedString
    public let modifiers: Modifiers
    public let annotations: [AnnotationNode]
    public let superTypes: [TypeRefID]
    public let superTypeEntries: [SuperTypeEntry]
    public let superTypeConstructorArgs: [CallArgument]
    public let nestedTypeAliases: [TypeAliasDecl]
    public let initBlocks: [FunctionBody]
    public let classBodyInitOrder: [ClassBodyInitMember]
    public let memberFunctions: [DeclID]
    public let memberProperties: [DeclID]
    public let nestedClasses: [DeclID]
    public let nestedObjects: [DeclID]

    public init(
        range: SourceRange,
        name: InternedString,
        modifiers: Modifiers,
        annotations: [AnnotationNode] = [],
        superTypes: [TypeRefID] = [],
        superTypeEntries: [SuperTypeEntry] = [],
        superTypeConstructorArgs: [CallArgument] = [],
        nestedTypeAliases: [TypeAliasDecl] = [],
        initBlocks: [FunctionBody] = [],
        classBodyInitOrder: [ClassBodyInitMember] = [],
        memberFunctions: [DeclID] = [],
        memberProperties: [DeclID] = [],
        nestedClasses: [DeclID] = [],
        nestedObjects: [DeclID] = []
    ) {
        self.range = range
        self.name = name
        self.modifiers = modifiers
        self.annotations = annotations
        self.superTypes = superTypes
        self.superTypeEntries = superTypeEntries.isEmpty
            ? superTypes.map { SuperTypeEntry(typeRef: $0) }
            : superTypeEntries
        self.superTypeConstructorArgs = superTypeConstructorArgs
        self.nestedTypeAliases = nestedTypeAliases
        self.initBlocks = initBlocks
        self.classBodyInitOrder = classBodyInitOrder
        self.memberFunctions = memberFunctions
        self.memberProperties = memberProperties
        self.nestedClasses = nestedClasses
        self.nestedObjects = nestedObjects
    }
}

/// AST-layer type names mirror Kotlin syntax keywords (e.g. `fun`),
/// while semantic/KIR layers use full English names (e.g. `Function`).
public struct FunDecl: Codable {
    public let range: SourceRange
    public let name: InternedString
    public let modifiers: Modifiers
    public let annotations: [AnnotationNode]
    public let typeParams: [TypeParamDecl]
    /// Source location of a declaration-level `where` clause, if present.
    /// The bounds themselves are stored on the declared type parameters.
    public let whereClauseRange: SourceRange?
    public let receiverType: TypeRefID?
    /// Declaration-level `context(...)` receivers. Names are nil for unnamed
    /// or `_:` parameters. These stay independent of `receiverType` so a
    /// member function's class `this` is not overwritten by a context type.
    public let contextReceivers: [ContextReceiverDecl]
    public var contextReceiverNames: [InternedString?] {
        contextReceivers.map(\.name)
    }
    public let valueParams: [ValueParamDecl]
    public let returnType: TypeRefID?
    public let body: FunctionBody
    public let isSuspend: Bool
    public let isInline: Bool
    public let isTailrec: Bool
    /// Marks the compiler-synthesized `main` wrapper for top-level script
    /// statements. It is not a source-declared callable, so package-scope
    /// duplicate checks must not compare it against a user-declared `main`.
    public let isScriptEntryPoint: Bool

    public init(
        range: SourceRange,
        name: InternedString,
        modifiers: Modifiers,
        annotations: [AnnotationNode] = [],
        typeParams: [TypeParamDecl] = [],
        whereClauseRange: SourceRange? = nil,
        receiverType: TypeRefID? = nil,
        contextReceivers: [ContextReceiverDecl] = [],
        valueParams: [ValueParamDecl] = [],
        returnType: TypeRefID? = nil,
        body: FunctionBody = .unit,
        isSuspend: Bool = false,
        isInline: Bool = false,
        isTailrec: Bool = false,
        isScriptEntryPoint: Bool = false
    ) {
        self.range = range
        self.name = name
        self.modifiers = modifiers
        self.annotations = annotations
        self.typeParams = typeParams
        self.whereClauseRange = whereClauseRange
        self.receiverType = receiverType
        self.contextReceivers = contextReceivers
        self.valueParams = valueParams
        self.returnType = returnType
        self.body = body
        self.isSuspend = isSuspend
        self.isInline = isInline
        self.isTailrec = isTailrec
        self.isScriptEntryPoint = isScriptEntryPoint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = try container.decode(SourceRange.self, forKey: .range)
        name = try container.decode(InternedString.self, forKey: .name)
        modifiers = try container.decode(Modifiers.self, forKey: .modifiers)
        annotations = try container.decode([AnnotationNode].self, forKey: .annotations)
        typeParams = try container.decode([TypeParamDecl].self, forKey: .typeParams)
        whereClauseRange = try container.decodeIfPresent(SourceRange.self, forKey: .whereClauseRange)
        receiverType = try container.decodeIfPresent(TypeRefID.self, forKey: .receiverType)
        contextReceivers = try container.decodeIfPresent([ContextReceiverDecl].self, forKey: .contextReceivers) ?? []
        valueParams = try container.decode([ValueParamDecl].self, forKey: .valueParams)
        returnType = try container.decodeIfPresent(TypeRefID.self, forKey: .returnType)
        body = try container.decode(FunctionBody.self, forKey: .body)
        isSuspend = try container.decode(Bool.self, forKey: .isSuspend)
        isInline = try container.decode(Bool.self, forKey: .isInline)
        isTailrec = try container.decode(Bool.self, forKey: .isTailrec)
        isScriptEntryPoint = try container.decodeIfPresent(Bool.self, forKey: .isScriptEntryPoint) ?? false
    }
}

public struct ContextReceiverDecl: Codable {
    public let name: InternedString?
    public let type: TypeRefID
    public let isContextParameter: Bool
    public let isCrossinline: Bool
    public let isNoinline: Bool

    public init(
        name: InternedString? = nil,
        type: TypeRefID,
        isContextParameter: Bool? = nil,
        isCrossinline: Bool = false,
        isNoinline: Bool = false
    ) {
        self.name = name
        self.type = type
        self.isContextParameter = isContextParameter ?? (name != nil)
        self.isCrossinline = isCrossinline
        self.isNoinline = isNoinline
    }

    private enum CodingKeys: String, CodingKey {
        case name, type, isContextParameter, isCrossinline, isNoinline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(InternedString.self, forKey: .name)
        type = try container.decode(TypeRefID.self, forKey: .type)
        isContextParameter = try container.decodeIfPresent(Bool.self, forKey: .isContextParameter)
            ?? (name != nil)
        isCrossinline = try container.decodeIfPresent(Bool.self, forKey: .isCrossinline) ?? false
        isNoinline = try container.decodeIfPresent(Bool.self, forKey: .isNoinline) ?? false
    }
}

public enum FunctionBody: Equatable, Codable {
    case block([ExprID], SourceRange)
    case expr(ExprID, SourceRange)
    case unit

    /// `fun f() = expr`-style expression bodies are the only bodies where a
    /// `return` targeting the function is prohibited outright.
    public var isExpressionBody: Bool {
        if case .expr = self { return true }
        return false
    }
}

public enum PropertyAccessorKind: Equatable, Codable {
    case getter
    case setter
}

public struct PropertyAccessorDecl: Equatable, Codable {
    public let range: SourceRange
    public let annotations: [AnnotationNode]
    public let kind: PropertyAccessorKind
    /// Explicit accessor visibility, or nil when it inherits the property's visibility.
    public let visibility: Visibility?
    public let isInline: Bool
    public let parameterName: InternedString?
    public let returnType: TypeRefID?
    public let body: FunctionBody

    public init(
        range: SourceRange,
        kind: PropertyAccessorKind,
        annotations: [AnnotationNode] = [],
        visibility: Visibility? = nil,
        isInline: Bool = false,
        parameterName: InternedString? = nil,
        returnType: TypeRefID? = nil,
        body: FunctionBody = .unit
    ) {
        self.range = range
        self.kind = kind
        self.annotations = annotations
        self.visibility = visibility
        self.isInline = isInline
        self.parameterName = parameterName
        self.returnType = returnType
        self.body = body
    }
}

public struct ExplicitBackingField: Codable {
    /// When `nil`, the type is inferred from the initializer expression.
    public let type: TypeRefID?
    public let initializer: ExprID

    public init(type: TypeRefID? = nil, initializer: ExprID) {
        self.type = type
        self.initializer = initializer
    }
}

public struct PropertyDecl: Codable {
    public let range: SourceRange
    public let name: InternedString
    public let modifiers: Modifiers
    public let annotations: [AnnotationNode]
    public let typeParams: [TypeParamDecl]
    public let type: TypeRefID?
    public let isVar: Bool
    public let initializer: ExprID?
    public let getter: PropertyAccessorDecl?
    public let setter: PropertyAccessorDecl?
    public let delegateExpression: ExprID?
    /// Captured separately so existing
    /// delegate lowering can reuse the call argument's parsed body.
    public let delegateBody: FunctionBody?
    public let delegateBodyParams: [InternedString]
    public let receiverType: TypeRefID?
    public let contextReceivers: [ContextReceiverDecl]
    public let isSynthesizedPrimaryConstructorProperty: Bool
    public let explicitBackingField: ExplicitBackingField?

    public var allAccessorsAreInline: Bool {
        modifiers.contains(.inline) || (getter?.isInline == true && (!isVar || setter?.isInline == true))
    }

    public init(
        range: SourceRange,
        name: InternedString,
        modifiers: Modifiers,
        annotations: [AnnotationNode] = [],
        typeParams: [TypeParamDecl] = [],
        type: TypeRefID?,
        isVar: Bool = false,
        initializer: ExprID? = nil,
        getter: PropertyAccessorDecl? = nil,
        setter: PropertyAccessorDecl? = nil,
        delegateExpression: ExprID? = nil,
        delegateBody: FunctionBody? = nil,
        delegateBodyParams: [InternedString] = [],
        receiverType: TypeRefID? = nil,
        contextReceivers: [ContextReceiverDecl] = [],
        isSynthesizedPrimaryConstructorProperty: Bool = false,
        explicitBackingField: ExplicitBackingField? = nil
    ) {
        self.range = range
        self.name = name
        self.modifiers = modifiers
        self.annotations = annotations
        self.typeParams = typeParams
        self.type = type
        self.isVar = isVar
        self.initializer = initializer
        self.getter = getter
        self.setter = setter
        self.delegateExpression = delegateExpression
        self.delegateBody = delegateBody
        self.delegateBodyParams = delegateBodyParams
        self.receiverType = receiverType
        self.contextReceivers = contextReceivers
        self.isSynthesizedPrimaryConstructorProperty = isSynthesizedPrimaryConstructorProperty
        self.explicitBackingField = explicitBackingField
    }

    private enum CodingKeys: String, CodingKey {
        case range, name, modifiers, annotations, typeParams, type, isVar, initializer
        case getter, setter, delegateExpression, delegateBody, delegateBodyParams
        case receiverType, contextReceivers, isSynthesizedPrimaryConstructorProperty
        case explicitBackingField
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = try container.decode(SourceRange.self, forKey: .range)
        name = try container.decode(InternedString.self, forKey: .name)
        modifiers = try container.decode(Modifiers.self, forKey: .modifiers)
        annotations = try container.decodeIfPresent([AnnotationNode].self, forKey: .annotations) ?? []
        typeParams = try container.decodeIfPresent([TypeParamDecl].self, forKey: .typeParams) ?? []
        type = try container.decodeIfPresent(TypeRefID.self, forKey: .type)
        isVar = try container.decodeIfPresent(Bool.self, forKey: .isVar) ?? false
        initializer = try container.decodeIfPresent(ExprID.self, forKey: .initializer)
        getter = try container.decodeIfPresent(PropertyAccessorDecl.self, forKey: .getter)
        setter = try container.decodeIfPresent(PropertyAccessorDecl.self, forKey: .setter)
        delegateExpression = try container.decodeIfPresent(ExprID.self, forKey: .delegateExpression)
        delegateBody = try container.decodeIfPresent(FunctionBody.self, forKey: .delegateBody)
        delegateBodyParams = try container.decodeIfPresent([InternedString].self, forKey: .delegateBodyParams) ?? []
        receiverType = try container.decodeIfPresent(TypeRefID.self, forKey: .receiverType)
        contextReceivers = try container.decodeIfPresent([ContextReceiverDecl].self, forKey: .contextReceivers) ?? []
        isSynthesizedPrimaryConstructorProperty = try container.decodeIfPresent(
            Bool.self, forKey: .isSynthesizedPrimaryConstructorProperty
        ) ?? false
        explicitBackingField = try container.decodeIfPresent(ExplicitBackingField.self, forKey: .explicitBackingField)
    }
}

public struct TypeAliasDecl: Codable {
    public let range: SourceRange
    public let name: InternedString
    public let modifiers: Modifiers
    public let annotations: [AnnotationNode]
    public let typeParams: [TypeParamDecl]
    public let underlyingType: TypeRefID?

    public init(
        range: SourceRange,
        name: InternedString,
        modifiers: Modifiers,
        annotations: [AnnotationNode] = [],
        typeParams: [TypeParamDecl] = [],
        underlyingType: TypeRefID? = nil
    ) {
        self.range = range
        self.name = name
        self.modifiers = modifiers
        self.annotations = annotations
        self.typeParams = typeParams
        self.underlyingType = underlyingType
    }
}

public struct EnumEntryDecl: Codable {
    public let range: SourceRange
    public let name: InternedString
    public let annotations: [AnnotationNode]
    public let constructorArgs: [CallArgument]
    public let initBlocks: [FunctionBody]
    /// Property initializers and init blocks execute in declaration order.
    public let classBodyInitOrder: [ClassBodyInitMember]
    /// These declarations are kept separate from the enum class members. The
    /// runtime still represents enum values as ordinals, so the lowering pass
    /// can synthesize ordinal-based dispatch for overrides without creating a
    /// second heap-backed representation for enum entries.
    public let memberFunctions: [DeclID]
    /// Like `memberFunctions`, they are
    /// owned by the entry field symbol; their values live in the per-entry
    /// side storage that the enum's lazy initializer fills.
    public let memberProperties: [DeclID]
    /// Nested classifier declarations belong to the entry scope while the
    /// entry value itself keeps the enum's ordinal-backed representation.
    public let nestedClasses: [DeclID]

    public init(
        range: SourceRange,
        name: InternedString,
        annotations: [AnnotationNode] = [],
        constructorArgs: [CallArgument] = [],
        initBlocks: [FunctionBody] = [],
        classBodyInitOrder: [ClassBodyInitMember] = [],
        memberFunctions: [DeclID] = [],
        memberProperties: [DeclID] = [],
        nestedClasses: [DeclID] = []
    ) {
        self.range = range
        self.name = name
        self.annotations = annotations
        self.constructorArgs = constructorArgs
        self.initBlocks = initBlocks
        self.classBodyInitOrder = classBodyInitOrder
        self.memberFunctions = memberFunctions
        self.memberProperties = memberProperties
        self.nestedClasses = nestedClasses
    }

    private enum CodingKeys: String, CodingKey {
        case range
        case name
        case annotations
        case constructorArgs
        case initBlocks
        case classBodyInitOrder
        case memberFunctions
        case memberProperties
        case nestedClasses
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = try container.decode(SourceRange.self, forKey: .range)
        name = try container.decode(InternedString.self, forKey: .name)
        annotations = try container.decodeIfPresent([AnnotationNode].self, forKey: .annotations) ?? []
        constructorArgs = try container.decodeIfPresent([CallArgument].self, forKey: .constructorArgs) ?? []
        initBlocks = try container.decodeIfPresent([FunctionBody].self, forKey: .initBlocks) ?? []
        classBodyInitOrder = try container.decodeIfPresent(
            [ClassBodyInitMember].self, forKey: .classBodyInitOrder
        ) ?? []
        memberFunctions = try container.decodeIfPresent([DeclID].self, forKey: .memberFunctions) ?? []
        memberProperties = try container.decodeIfPresent([DeclID].self, forKey: .memberProperties) ?? []
        nestedClasses = try container.decodeIfPresent([DeclID].self, forKey: .nestedClasses) ?? []
    }
}

public struct ImportDecl: Sendable, Codable {
    public let range: SourceRange
    public let path: [InternedString]
    public let alias: InternedString?
    public let isWildcard: Bool

    private enum CodingKeys: String, CodingKey {
        case range
        case path
        case alias
        case isWildcard
    }

    public init(
        range: SourceRange,
        path: [InternedString],
        alias: InternedString? = nil,
        isWildcard: Bool = false
    ) {
        self.range = range
        self.path = path
        self.alias = alias
        self.isWildcard = isWildcard
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = try container.decode(SourceRange.self, forKey: .range)
        path = try container.decode([InternedString].self, forKey: .path)
        alias = try container.decodeIfPresent(InternedString.self, forKey: .alias)
        // Older frontend caches did not record whether an import was wildcard.
        isWildcard = try container.decodeIfPresent(Bool.self, forKey: .isWildcard) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(range, forKey: .range)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(alias, forKey: .alias)
        try container.encode(isWildcard, forKey: .isWildcard)
    }
}

public struct TypeParamDecl: Equatable, Codable {
    public let name: InternedString
    public let variance: TypeVariance
    public let isReified: Bool
    public let upperBounds: [TypeRefID]
    public let annotations: [AnnotationNode]

    public init(
        name: InternedString,
        variance: TypeVariance = .invariant,
        isReified: Bool = false,
        upperBounds: [TypeRefID] = [],
        annotations: [AnnotationNode] = []
    ) {
        self.name = name
        self.variance = variance
        self.isReified = isReified
        self.upperBounds = upperBounds
        self.annotations = annotations
    }

    private enum CodingKeys: String, CodingKey {
        case name, variance, isReified, upperBounds, annotations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(InternedString.self, forKey: .name)
        variance = try container.decode(TypeVariance.self, forKey: .variance)
        isReified = try container.decode(Bool.self, forKey: .isReified)
        upperBounds = try container.decode([TypeRefID].self, forKey: .upperBounds)
        annotations = try container.decodeIfPresent([AnnotationNode].self, forKey: .annotations) ?? []
    }
}

public struct ValueParamDecl: Equatable, Codable {
    public let name: InternedString
    public let type: TypeRefID?
    public let isProperty: Bool
    public let isMutableProperty: Bool
    public let isOverrideProperty: Bool
    public let isOpenProperty: Bool
    /// `true` when a primary constructor property parameter carries `actual`.
    public let isActualProperty: Bool
    /// Optional so AST
    /// payloads written before this field was introduced retain default visibility.
    public let propertyVisibilityModifiers: Modifiers?
    public let hasDefaultValue: Bool
    public let isVararg: Bool
    /// Source range of the `vararg` modifier, when present.
    public let varargRange: SourceRange?
    public let isCrossinline: Bool
    public let isNoinline: Bool
    public let defaultValue: ExprID?
    public let annotations: [AnnotationNode]

    public init(
        name: InternedString,
        type: TypeRefID?,
        isProperty: Bool = false,
        isMutableProperty: Bool = false,
        isOverrideProperty: Bool = false,
        isOpenProperty: Bool = false,
        isActualProperty: Bool = false,
        propertyVisibilityModifiers: Modifiers? = nil,
        hasDefaultValue: Bool = false,
        isVararg: Bool = false,
        varargRange: SourceRange? = nil,
        isCrossinline: Bool = false,
        isNoinline: Bool = false,
        defaultValue: ExprID? = nil,
        annotations: [AnnotationNode] = []
    ) {
        self.name = name
        self.type = type
        self.isProperty = isProperty
        self.isMutableProperty = isMutableProperty
        self.isOverrideProperty = isOverrideProperty
        self.isOpenProperty = isOpenProperty
        self.isActualProperty = isActualProperty
        self.propertyVisibilityModifiers = propertyVisibilityModifiers
        self.hasDefaultValue = hasDefaultValue
        self.isVararg = isVararg
        self.varargRange = varargRange
        self.isCrossinline = isCrossinline
        self.isNoinline = isNoinline
        self.defaultValue = defaultValue
        self.annotations = annotations
    }

    private enum CodingKeys: String, CodingKey {
        case name, type, isProperty, isMutableProperty, isOverrideProperty, isOpenProperty
        case isActualProperty, propertyVisibilityModifiers, hasDefaultValue, isVararg
        case varargRange, isCrossinline, isNoinline, defaultValue, annotations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(InternedString.self, forKey: .name)
        type = try container.decodeIfPresent(TypeRefID.self, forKey: .type)
        isProperty = try container.decode(Bool.self, forKey: .isProperty)
        isMutableProperty = try container.decode(Bool.self, forKey: .isMutableProperty)
        isOverrideProperty = try container.decode(Bool.self, forKey: .isOverrideProperty)
        isOpenProperty = try container.decode(Bool.self, forKey: .isOpenProperty)
        isActualProperty = try container.decodeIfPresent(Bool.self, forKey: .isActualProperty) ?? false
        propertyVisibilityModifiers = try container.decodeIfPresent(Modifiers.self, forKey: .propertyVisibilityModifiers)
        hasDefaultValue = try container.decode(Bool.self, forKey: .hasDefaultValue)
        isVararg = try container.decode(Bool.self, forKey: .isVararg)
        varargRange = try container.decodeIfPresent(SourceRange.self, forKey: .varargRange)
        isCrossinline = try container.decode(Bool.self, forKey: .isCrossinline)
        isNoinline = try container.decode(Bool.self, forKey: .isNoinline)
        defaultValue = try container.decodeIfPresent(ExprID.self, forKey: .defaultValue)
        annotations = try container.decodeIfPresent([AnnotationNode].self, forKey: .annotations) ?? []
    }
}

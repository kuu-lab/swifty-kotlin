public struct AnnotationNode: Equatable, Codable {
    public let name: String
    public let arguments: [String]
    public let useSiteTarget: String?

    public init(name: String, arguments: [String] = [], useSiteTarget: String? = nil) {
        self.name = name
        self.arguments = arguments
        self.useSiteTarget = useSiteTarget
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
    public let delegateExpression: ExprID?
    public let constructorArgs: [CallArgument]

    public init(
        typeRef: TypeRefID,
        delegateExpression: ExprID? = nil,
        constructorArgs: [CallArgument] = []
    ) {
        self.typeRef = typeRef
        self.delegateExpression = delegateExpression
        self.constructorArgs = constructorArgs
    }
}

/// Used to guarantee Kotlin's declaration-order execution of property
/// initializers and `init` blocks.
public enum ClassBodyInitMember: Equatable, Codable {
    case property(Int)
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
    public let receiverType: TypeRefID?
    /// These stay independent of `receiverType` so a
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

    public init(
        range: SourceRange,
        name: InternedString,
        modifiers: Modifiers,
        annotations: [AnnotationNode] = [],
        typeParams: [TypeParamDecl] = [],
        receiverType: TypeRefID? = nil,
        contextReceivers: [ContextReceiverDecl] = [],
        valueParams: [ValueParamDecl] = [],
        returnType: TypeRefID? = nil,
        body: FunctionBody = .unit,
        isSuspend: Bool = false,
        isInline: Bool = false,
        isTailrec: Bool = false
    ) {
        self.range = range
        self.name = name
        self.modifiers = modifiers
        self.annotations = annotations
        self.typeParams = typeParams
        self.receiverType = receiverType
        self.contextReceivers = contextReceivers
        self.valueParams = valueParams
        self.returnType = returnType
        self.body = body
        self.isSuspend = isSuspend
        self.isInline = isInline
        self.isTailrec = isTailrec
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = try container.decode(SourceRange.self, forKey: .range)
        name = try container.decode(InternedString.self, forKey: .name)
        modifiers = try container.decode(Modifiers.self, forKey: .modifiers)
        annotations = try container.decode([AnnotationNode].self, forKey: .annotations)
        typeParams = try container.decode([TypeParamDecl].self, forKey: .typeParams)
        receiverType = try container.decodeIfPresent(TypeRefID.self, forKey: .receiverType)
        contextReceivers = try container.decodeIfPresent([ContextReceiverDecl].self, forKey: .contextReceivers) ?? []
        valueParams = try container.decode([ValueParamDecl].self, forKey: .valueParams)
        returnType = try container.decodeIfPresent(TypeRefID.self, forKey: .returnType)
        body = try container.decode(FunctionBody.self, forKey: .body)
        isSuspend = try container.decode(Bool.self, forKey: .isSuspend)
        isInline = try container.decode(Bool.self, forKey: .isInline)
        isTailrec = try container.decode(Bool.self, forKey: .isTailrec)
    }
}

public struct ContextReceiverDecl: Codable {
    public let name: InternedString?
    public let type: TypeRefID

    public init(name: InternedString? = nil, type: TypeRefID) {
        self.name = name
        self.type = type
    }
}

public enum FunctionBody: Equatable, Codable {
    case block([ExprID], SourceRange)
    case expr(ExprID, SourceRange)
    case unit
}

public enum PropertyAccessorKind: Equatable, Codable {
    case getter
    case setter
}

public struct PropertyAccessorDecl: Equatable, Codable {
    public let range: SourceRange
    public let annotations: [AnnotationNode]
    public let kind: PropertyAccessorKind
    public let visibility: Visibility?
    public let parameterName: InternedString?
    public let body: FunctionBody

    public init(
        range: SourceRange,
        kind: PropertyAccessorKind,
        annotations: [AnnotationNode] = [],
        visibility: Visibility? = nil,
        parameterName: InternedString? = nil,
        body: FunctionBody = .unit
    ) {
        self.range = range
        self.kind = kind
        self.annotations = annotations
        self.visibility = visibility
        self.parameterName = parameterName
        self.body = body
    }
}

public struct ExplicitBackingField: Codable {
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
    public let isSynthesizedPrimaryConstructorProperty: Bool
    public let explicitBackingField: ExplicitBackingField?

    public init(
        range: SourceRange,
        name: InternedString,
        modifiers: Modifiers,
        annotations: [AnnotationNode] = [],
        type: TypeRefID?,
        isVar: Bool = false,
        initializer: ExprID? = nil,
        getter: PropertyAccessorDecl? = nil,
        setter: PropertyAccessorDecl? = nil,
        delegateExpression: ExprID? = nil,
        delegateBody: FunctionBody? = nil,
        delegateBodyParams: [InternedString] = [],
        receiverType: TypeRefID? = nil,
        isSynthesizedPrimaryConstructorProperty: Bool = false,
        explicitBackingField: ExplicitBackingField? = nil
    ) {
        self.range = range
        self.name = name
        self.modifiers = modifiers
        self.annotations = annotations
        self.type = type
        self.isVar = isVar
        self.initializer = initializer
        self.getter = getter
        self.setter = setter
        self.delegateExpression = delegateExpression
        self.delegateBody = delegateBody
        self.delegateBodyParams = delegateBodyParams
        self.receiverType = receiverType
        self.isSynthesizedPrimaryConstructorProperty = isSynthesizedPrimaryConstructorProperty
        self.explicitBackingField = explicitBackingField
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
    /// These declarations are kept separate from the enum class members. The
    /// runtime still represents enum values as ordinals, so the lowering pass
    /// can synthesize ordinal-based dispatch for overrides without creating a
    /// second heap-backed representation for enum entries.
    public let memberFunctions: [DeclID]
    /// Like `memberFunctions`, they are
    /// owned by the entry field symbol; their values live in the per-entry
    /// side storage that the enum's lazy initializer fills.
    public let memberProperties: [DeclID]

    public init(
        range: SourceRange,
        name: InternedString,
        annotations: [AnnotationNode] = [],
        constructorArgs: [CallArgument] = [],
        memberFunctions: [DeclID] = [],
        memberProperties: [DeclID] = []
    ) {
        self.range = range
        self.name = name
        self.annotations = annotations
        self.constructorArgs = constructorArgs
        self.memberFunctions = memberFunctions
        self.memberProperties = memberProperties
    }
}

public extension EnumEntryDecl {
    func constructorArgumentMapping(
        parameterNames: [InternedString]
    ) -> (argumentIndexByParameter: [Int?], unmatched: [Int]) {
        var mapping = [Int?](repeating: nil, count: parameterNames.count)
        var unmatched: [Int] = []
        var nextPositional = 0
        for (argIndex, arg) in constructorArgs.enumerated() {
            if let label = arg.label {
                if let paramIndex = parameterNames.firstIndex(of: label), mapping[paramIndex] == nil {
                    mapping[paramIndex] = argIndex
                } else {
                    unmatched.append(argIndex)
                }
                continue
            }
            if nextPositional < parameterNames.count {
                mapping[nextPositional] = argIndex
                nextPositional += 1
            } else {
                unmatched.append(argIndex)
            }
        }
        return (mapping, unmatched)
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

public struct TypeParamDecl: Codable {
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
    /// Optional so AST
    /// payloads written before this field was introduced retain default visibility.
    public let propertyVisibilityModifiers: Modifiers?
    public let hasDefaultValue: Bool
    public let isVararg: Bool
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
        propertyVisibilityModifiers: Modifiers? = nil,
        hasDefaultValue: Bool = false,
        isVararg: Bool = false,
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
        self.propertyVisibilityModifiers = propertyVisibilityModifiers
        self.hasDefaultValue = hasDefaultValue
        self.isVararg = isVararg
        self.isCrossinline = isCrossinline
        self.isNoinline = isNoinline
        self.defaultValue = defaultValue
        self.annotations = annotations
    }
}

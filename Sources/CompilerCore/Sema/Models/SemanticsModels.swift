public struct SymbolID: Hashable, Sendable, Codable {
    public let rawValue: Int32

    public static let invalid = SymbolID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }
}

public enum SymbolKind: Hashable, Sendable, Codable {
    case package
    case `class`
    case interface
    case object
    case enumClass
    case annotationClass
    case typeAlias
    case function
    case constructor
    case property
    case field
    case backingField
    case typeParameter
    case valueParameter
    case local
    case label
}

public struct SymbolFlags: OptionSet, Sendable, Codable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let suspendFunction = SymbolFlags(rawValue: 1 << 0)
    public static let inlineFunction = SymbolFlags(rawValue: 1 << 1)
    public static let mutable = SymbolFlags(rawValue: 1 << 2)
    public static let synthetic = SymbolFlags(rawValue: 1 << 3)
    public static let `static` = SymbolFlags(rawValue: 1 << 4)
    public static let sealedType = SymbolFlags(rawValue: 1 << 5)
    public static let dataType = SymbolFlags(rawValue: 1 << 6)
    public static let reifiedTypeParameter = SymbolFlags(rawValue: 1 << 7)
    public static let innerClass = SymbolFlags(rawValue: 1 << 8)
    public static let valueType = SymbolFlags(rawValue: 1 << 9)
    public static let operatorFunction = SymbolFlags(rawValue: 1 << 10)
    public static let constValue = SymbolFlags(rawValue: 1 << 11)
    public static let abstractType = SymbolFlags(rawValue: 1 << 12)
    public static let openType = SymbolFlags(rawValue: 1 << 13)
    public static let overrideMember = SymbolFlags(rawValue: 1 << 14)
    public static let finalMember = SymbolFlags(rawValue: 1 << 15)
    public static let funInterface = SymbolFlags(rawValue: 1 << 16)
    public static let expectDeclaration = SymbolFlags(rawValue: 1 << 17)
    public static let actualDeclaration = SymbolFlags(rawValue: 1 << 18)
    public static let lateinitProperty = SymbolFlags(rawValue: 1 << 19)
    /// Marks a synthetic stub function as one that passes an outThrown pointer
    /// to signal ArithmeticException / NumberFormatException at runtime.
    /// The ABI lowering pass must NOT add this symbol to nonThrowingCallees.
    public static let throwingFunction = SymbolFlags(rawValue: 1 << 20)
    public static let readOnlyProperty = SymbolFlags(rawValue: 1 << 21)
    public static let importedLibrary = SymbolFlags(rawValue: 1 << 22)
    /// Marks a constructor whose stored `visibility` was copied down from its
    /// owning class/object because the constructor itself had no explicit
    /// visibility modifier (see `constructorVisibilityDetail`). `VisibilityChecker`
    /// uses this to fall back to the owner's own accessibility rule (e.g. file
    /// scope for a top-level `private class`) instead of a class-hierarchy check,
    /// without loosening genuinely explicit `private constructor` declarations.
    public static let constructorVisibilityInherited = SymbolFlags(rawValue: 1 << 23)
    /// Marks the synthetic member alias created for a source-backed bundled
    /// extension function under its receiver nominal's FQ name (KSP-443). The
    /// alias exists solely for owner+member-name lookup — it is statically
    /// dispatched through its external link name and must never occupy a
    /// vtable/itable slot or be treated as a real member of the nominal
    /// (KUU-545).
    public static let extensionMemberAlias = SymbolFlags(rawValue: 1 << 24)
    public static let localFunction = SymbolFlags(rawValue: 1 << 25)
    public static let memberExtension = SymbolFlags(rawValue: 1 << 26)
    public static let infixFunction = SymbolFlags(rawValue: 1 << 27)
    /// Imported before allocation-component descriptors were part of source ABI.
    public static let legacyReifiedClassTokenABI = SymbolFlags(rawValue: 1 << 28)
    /// This declaration was synthesized by the compiler's stdlib bootstrap
    /// registry and is serialized into newly built stdlib artifacts.
    public static let precomputedStdlibSynthetic = SymbolFlags(rawValue: 1 << 29)
    /// The owning library object already contains this symbol's runtime
    /// reflection record, so consumers must not rebuild it.
    public static let precomputedRuntimeReflection = SymbolFlags(rawValue: 1 << 30)
    /// Marks the synthetic class that represents an anonymous object literal.
    /// Its type is usable only within the source file that declares the literal.
    public static let objectLiteralType = SymbolFlags(rawValue: UInt32(1) << 31)
}

extension SymbolFlags {
    init(modifiers: Modifiers) {
        self.init(rawValue: 0)
        // Value-class status is declaration-kind-specific and is assigned by
        // class header collection rather than from modifiers alone.
        if modifiers.contains(.suspend) { insert(.suspendFunction) }
        if modifiers.contains(.inline) { insert(.inlineFunction) }
        if modifiers.contains(.operator) { insert(.operatorFunction) }
        if modifiers.contains(.infix) { insert(.infixFunction) }
        if modifiers.contains(.sealed) { insert(.sealedType) }
        if modifiers.contains(.data) { insert(.dataType) }
        if modifiers.contains(.inner) { insert(.innerClass) }
        if modifiers.contains(.abstract) { insert(.abstractType) }
        if modifiers.contains(.open) { insert(.openType) }
        if modifiers.contains(.const) { insert(.constValue) }
        if modifiers.contains(.override) { insert(.overrideMember) }
        if modifiers.contains(.final) { insert(.finalMember) }
        if modifiers.contains(.expect) { insert(.expectDeclaration) }
        if modifiers.contains(.actual) { insert(.actualDeclaration) }
        if modifiers.contains(.lateinit) { insert(.lateinitProperty) }
    }
}

public struct SemanticSymbol: Sendable {
    public let id: SymbolID
    public let kind: SymbolKind
    public let name: InternedString
    public let fqName: [InternedString]
    public var declSite: SourceRange?
    public let visibility: Visibility
    public var flags: SymbolFlags
}

func isCompatibleExpectActualPair(
    newKind: SymbolKind,
    newFlags: SymbolFlags,
    existing: SemanticSymbol
) -> Bool {
    let isNewExpect = newFlags.contains(.expectDeclaration)
    let isNewActual = newFlags.contains(.actualDeclaration)
    guard isNewExpect != isNewActual else {
        return false
    }

    let hasExistingExpect = existing.flags.contains(.expectDeclaration)
    let hasExistingActual = existing.flags.contains(.actualDeclaration)
    guard hasExistingExpect != hasExistingActual else {
        return false
    }

    if isNewExpect {
        guard hasExistingActual else {
            return false
        }
        return newKind == existing.kind
            || (newKind == .annotationClass && existing.kind == .typeAlias)
            || (newKind == .class && existing.kind == .typeAlias)
    }

    guard hasExistingExpect else {
        return false
    }
    return newKind == existing.kind
        || (newKind == .typeAlias && (existing.kind == .annotationClass || existing.kind == .class))
}

public struct FunctionSignature: Hashable, Sendable, Codable {
    public let receiverType: TypeID?
    public let contextReceiverTypes: [TypeID]
    public let contextParameterSymbols: [SymbolID]
    public let contextParameterTypes: [TypeID]
    public let parameterTypes: [TypeID]
    public let returnType: TypeID
    public let isSuspend: Bool
    public let canThrow: Bool
    public let valueParameterSymbols: [SymbolID]
    /// Per-value-parameter type parameters whose use is explicitly marked
    /// `@UnsafeVariance`. The annotation is type-use metadata, so keep the
    /// resolved type-parameter symbols after resolving the parameter type.
    public let valueParameterUnsafeVarianceTypeParameterSymbols: [Set<SymbolID>]
    public let valueParameterHasDefaultValues: [Bool]
    public let valueParameterIsVararg: [Bool]
    /// Whether a function parameter may carry non-local returns from a lambda
    /// argument. `crossinline` and `noinline` parameters are false.
    public let valueParameterAllowsNonLocalReturn: [Bool]
    /// False for legacy imported signatures whose inline permissions were inferred.
    public let hasExplicitInlineParameterMetadata: Bool
    /// Whether callers may rely on the declaration's value-parameter names.
    /// Java methods have names in their class metadata, but Kotlin/JVM does not
    /// permit callers to use them as named arguments.
    public let hasStableParameterNames: Bool
    public let typeParameterSymbols: [SymbolID]
    public let reifiedTypeParameterIndices: Set<Int>
    public let typeParameterUpperBounds: [TypeID?]
    public let typeParameterUpperBoundsList: [[TypeID]]
    /// Number of leading entries in `typeParameterSymbols` that belong to the
    /// enclosing class/interface (not the function itself).  The overload resolver
    /// skips these when matching explicit type arguments and offsetting reified
    /// indices.  Defaults to 0 for non-member or non-generic-class functions.
    public let classTypeParameterCount: Int

    public init(
        receiverType: TypeID? = nil,
        contextReceiverTypes: [TypeID] = [],
        contextParameterSymbols: [SymbolID] = [],
        contextParameterTypes: [TypeID] = [],
        parameterTypes: [TypeID],
        returnType: TypeID,
        isSuspend: Bool = false,
        canThrow: Bool = false,
        valueParameterSymbols: [SymbolID] = [],
        valueParameterUnsafeVarianceTypeParameterSymbols: [Set<SymbolID>] = [],
        valueParameterHasDefaultValues: [Bool] = [],
        valueParameterIsVararg: [Bool] = [],
        valueParameterAllowsNonLocalReturn: [Bool] = [],
        hasExplicitInlineParameterMetadata: Bool = true,
        hasStableParameterNames: Bool = true,
        typeParameterSymbols: [SymbolID] = [],
        reifiedTypeParameterIndices: Set<Int> = [],
        typeParameterUpperBounds: [TypeID?] = [],
        typeParameterUpperBoundsList: [[TypeID]] = [],
        classTypeParameterCount: Int = 0
    ) {
        self.receiverType = receiverType
        self.contextReceiverTypes = contextReceiverTypes
        self.contextParameterSymbols = contextParameterSymbols
        self.contextParameterTypes = contextParameterTypes
        self.parameterTypes = parameterTypes
        self.returnType = returnType
        self.isSuspend = isSuspend
        self.canThrow = canThrow
        self.valueParameterSymbols = valueParameterSymbols
        self.valueParameterUnsafeVarianceTypeParameterSymbols = valueParameterUnsafeVarianceTypeParameterSymbols
        self.valueParameterHasDefaultValues = valueParameterHasDefaultValues
        self.valueParameterIsVararg = valueParameterIsVararg
        self.valueParameterAllowsNonLocalReturn = valueParameterAllowsNonLocalReturn
        self.hasExplicitInlineParameterMetadata = hasExplicitInlineParameterMetadata
        self.hasStableParameterNames = hasStableParameterNames
        self.typeParameterSymbols = typeParameterSymbols
        self.reifiedTypeParameterIndices = reifiedTypeParameterIndices
        let normalizedUpperBoundsList: [[TypeID]] = if !typeParameterUpperBoundsList.isEmpty {
            typeParameterUpperBoundsList
        } else {
            typeParameterUpperBounds.map { bound in
                bound.map { [$0] } ?? []
            }
        }
        self.typeParameterUpperBoundsList = normalizedUpperBoundsList
        self.typeParameterUpperBounds = normalizedUpperBoundsList.map(\.first)
        self.classTypeParameterCount = classTypeParameterCount
    }

    func replacingReturnType(_ returnType: TypeID) -> FunctionSignature {
        FunctionSignature(
            receiverType: receiverType,
            contextReceiverTypes: contextReceiverTypes,
            contextParameterSymbols: contextParameterSymbols,
            contextParameterTypes: contextParameterTypes,
            parameterTypes: parameterTypes,
            returnType: returnType,
            isSuspend: isSuspend,
            canThrow: canThrow,
            valueParameterSymbols: valueParameterSymbols,
            valueParameterUnsafeVarianceTypeParameterSymbols: valueParameterUnsafeVarianceTypeParameterSymbols,
            valueParameterHasDefaultValues: valueParameterHasDefaultValues,
            valueParameterIsVararg: valueParameterIsVararg,
            valueParameterAllowsNonLocalReturn: valueParameterAllowsNonLocalReturn,
            hasExplicitInlineParameterMetadata: hasExplicitInlineParameterMetadata,
            hasStableParameterNames: hasStableParameterNames,
            typeParameterSymbols: typeParameterSymbols,
            reifiedTypeParameterIndices: reifiedTypeParameterIndices,
            typeParameterUpperBounds: typeParameterUpperBounds,
            typeParameterUpperBoundsList: typeParameterUpperBoundsList,
            classTypeParameterCount: classTypeParameterCount
        )
    }

    private enum CodingKeys: String, CodingKey {
        case receiverType
        case contextReceiverTypes
        case contextParameterSymbols
        case contextParameterTypes
        case parameterTypes
        case returnType
        case isSuspend
        case canThrow
        case valueParameterSymbols
        case valueParameterUnsafeVarianceTypeParameterSymbols
        case valueParameterHasDefaultValues
        case valueParameterIsVararg
        case valueParameterAllowsNonLocalReturn
        case hasExplicitInlineParameterMetadata
        case hasStableParameterNames
        case typeParameterSymbols
        case reifiedTypeParameterIndices
        case typeParameterUpperBounds
        case typeParameterUpperBoundsList
        case classTypeParameterCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            receiverType: try container.decodeIfPresent(TypeID.self, forKey: .receiverType),
            contextReceiverTypes: try container.decode([TypeID].self, forKey: .contextReceiverTypes),
            contextParameterSymbols: try container.decode([SymbolID].self, forKey: .contextParameterSymbols),
            contextParameterTypes: try container.decode([TypeID].self, forKey: .contextParameterTypes),
            parameterTypes: try container.decode([TypeID].self, forKey: .parameterTypes),
            returnType: try container.decode(TypeID.self, forKey: .returnType),
            isSuspend: try container.decode(Bool.self, forKey: .isSuspend),
            canThrow: try container.decode(Bool.self, forKey: .canThrow),
            valueParameterSymbols: try container.decode([SymbolID].self, forKey: .valueParameterSymbols),
            valueParameterUnsafeVarianceTypeParameterSymbols: try container.decode(
                [Set<SymbolID>].self,
                forKey: .valueParameterUnsafeVarianceTypeParameterSymbols
            ),
            valueParameterHasDefaultValues: try container.decode([Bool].self, forKey: .valueParameterHasDefaultValues),
            valueParameterIsVararg: try container.decode([Bool].self, forKey: .valueParameterIsVararg),
            valueParameterAllowsNonLocalReturn: try container.decode([Bool].self, forKey: .valueParameterAllowsNonLocalReturn),
            hasExplicitInlineParameterMetadata: try container.decode(Bool.self, forKey: .hasExplicitInlineParameterMetadata),
            hasStableParameterNames: try container.decodeIfPresent(Bool.self, forKey: .hasStableParameterNames) ?? true,
            typeParameterSymbols: try container.decode([SymbolID].self, forKey: .typeParameterSymbols),
            reifiedTypeParameterIndices: try container.decode(Set<Int>.self, forKey: .reifiedTypeParameterIndices),
            typeParameterUpperBounds: try container.decode([TypeID?].self, forKey: .typeParameterUpperBounds),
            typeParameterUpperBoundsList: try container.decode([[TypeID]].self, forKey: .typeParameterUpperBoundsList),
            classTypeParameterCount: try container.decode(Int.self, forKey: .classTypeParameterCount)
        )
    }
}

public struct EnumEntryDispatchTarget: Hashable, Sendable, Codable {
    public let entrySymbol: SymbolID
    public let functionSymbol: SymbolID

    public init(entrySymbol: SymbolID, functionSymbol: SymbolID) {
        self.entrySymbol = entrySymbol
        self.functionSymbol = functionSymbol
    }
}

public struct NominalLayout: Equatable, Sendable, Codable {
    public let objectHeaderWords: Int
    public let instanceFieldCount: Int
    public let instanceSizeWords: Int
    public let fieldOffsets: [SymbolID: Int]
    public let vtableSlots: [SymbolID: Int]
    public let itableSlots: [SymbolID: Int]
    public let vtableSize: Int
    public let itableSize: Int
    public let superClass: SymbolID?

    public init(
        objectHeaderWords: Int,
        instanceFieldCount: Int,
        instanceSizeWords: Int,
        fieldOffsets: [SymbolID: Int] = [:],
        vtableSlots: [SymbolID: Int],
        itableSlots: [SymbolID: Int],
        vtableSize: Int? = nil,
        itableSize: Int? = nil,
        superClass: SymbolID?
    ) {
        self.objectHeaderWords = objectHeaderWords
        let inferredFieldCount = max(0, fieldOffsets.count)
        self.instanceFieldCount = max(instanceFieldCount, inferredFieldCount)
        let inferredInstanceSizeWords = max(0, (fieldOffsets.values.max() ?? (objectHeaderWords - 1)) + 1)
        self.instanceSizeWords = max(
            max(instanceSizeWords, inferredInstanceSizeWords),
            objectHeaderWords + self.instanceFieldCount
        )
        self.fieldOffsets = fieldOffsets
        self.vtableSlots = vtableSlots
        self.itableSlots = itableSlots
        let inferredVtableSize = (vtableSlots.values.max() ?? -1) + 1
        let inferredItableSize = (itableSlots.values.max() ?? -1) + 1
        self.vtableSize = max(0, max(vtableSize ?? 0, inferredVtableSize))
        self.itableSize = max(0, max(itableSize ?? 0, inferredItableSize))
        self.superClass = superClass
    }
}

public struct NominalLayoutHint: Equatable, Sendable, Codable {
    public let declaredFieldCount: Int?
    public let declaredInstanceSizeWords: Int?
    public let declaredVtableSize: Int?
    public let declaredItableSize: Int?

    public init(
        declaredFieldCount: Int?,
        declaredInstanceSizeWords: Int?,
        declaredVtableSize: Int?,
        declaredItableSize: Int?
    ) {
        self.declaredFieldCount = declaredFieldCount
        self.declaredInstanceSizeWords = declaredInstanceSizeWords
        self.declaredVtableSize = declaredVtableSize
        self.declaredItableSize = declaredItableSize
    }
}

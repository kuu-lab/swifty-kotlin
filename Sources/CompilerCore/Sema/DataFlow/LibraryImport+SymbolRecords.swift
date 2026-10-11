extension DataFlowSemaPhase {
    struct ImportedFieldOffsetEntry {
        let fqName: [InternedString]
        let offset: Int
    }

    struct ImportedVTableSlotEntry {
        let fqName: [InternedString]
        let arity: Int
        let isSuspend: Bool
        let slot: Int
        let typeSignature: String?
        let propertyAccessorKind: PropertyAccessorKind?
    }

    struct ImportedITableSlotEntry {
        let fqName: [InternedString]
        let slot: Int
    }

    struct ImportedLibrarySymbolRecord {
        let kind: SymbolKind
        let visibility: Visibility
        let mangledName: String
        let fqName: [InternedString]
        let arity: Int
        let isSuspend: Bool
        let isInline: Bool
        let isOperator: Bool
        let isInfix: Bool
        let isOverride: Bool
        let isMemberExtension: Bool
        let receiverOwnerFQName: [InternedString]?
        let valueParameterIsVararg: [Bool]
        let valueParameterAllowsNonLocalReturn: [Bool]
        let valueParameterHasDefaultValues: [Bool]
        /// STDLIB-592: per-parameter `contract { callsInPlace(param, kind) }` effect
        /// decoded from metadata, `nil` where the parameter has none.
        let valueParameterCallsInPlaceKinds: [InvocationKind?]
        let contractImplicationEffects: [ContractImplicationEffect]
        let canThrow: Bool
        let valueParameterNames: [String]
        let reifiedTypeParameterIndices: Set<Int>
        let typeSignature: String?
        let typeParameterUpperBoundsSignatures: [[String]]
        /// The callable's type parameters in declaration order, encoded as
        /// `T<rawID>` tokens (including any leading owner type parameters of
        /// member callables). Present on artifacts emitted by compilers that
        /// serialize `callTParams`; empty for older artifacts, where the
        /// structural scan plus the phantom-count fallback apply instead.
        let callableTypeParameterSignatures: [String]
        let inputOnlyTypeParameterIndices: Set<Int>
        let defaultStubExternalLinkName: String?
        let externalLinkName: String?
        let declaredFieldCount: Int?
        let declaredInstanceSizeWords: Int?
        let declaredVtableSize: Int?
        let declaredItableSize: Int?
        let superFQName: [InternedString]?
        let superFQNames: [[InternedString]]?
        let companionObjectFQName: [InternedString]?
        let fieldOffsets: [ImportedFieldOffsetEntry]
        let vtableSlots: [ImportedVTableSlotEntry]
        let itableSlots: [ImportedITableSlotEntry]
        let objectInitializerLinkName: String?
        let companionInitializerLinkName: String?
        let objectLazyInitializerLinkName: String?
        let enumStaticInitLinkName: String?
        let isDataClass: Bool
        let isOpenClass: Bool
        let modality: MetadataModality
        let isSealedClass: Bool
        let isFunInterface: Bool
        let isValueClass: Bool
        let isExpect: Bool
        let isActual: Bool
        let valueClassUnderlyingTypeSig: String?
        let annotations: [MetadataAnnotationRecord]
        let sealedSubclassFQNames: [[InternedString]]
        let propertyReceiverTypeSignature: String?
        let propertyGetterExternalLinkName: String?
        let propertySetterExternalLinkName: String?
        let abiReturnTypeSignature: String?
        let propertyGetterAbiReturnTypeSignature: String?
        let isMutable: Bool
        let nominalTypeParametersSignature: String?
        /// Generic self-signature of the nominal owner, when this record is a
        /// member. It lets imported member types replace metadata placeholders
        /// with the owner's actual type-parameter symbols.
        let ownerNominalTypeParametersSignature: String?
        let nominalSupertypeSignatures: [String]
        let constValueLiteral: String?
        /// Declaration-order type parameters of a nominal type, encoded as
        /// `<typeSignature>:<variance>` pairs (e.g. `T5023:i`).
        let nominalTypeParameters: String?

        init(
            kind: SymbolKind,
            visibility: Visibility = .public,
            mangledName: String = "",
            fqName: [InternedString] = [],
            arity: Int = 0,
            isSuspend: Bool = false,
            isInline: Bool = false,
            isOperator: Bool = false,
            isInfix: Bool = false,
            isOverride: Bool = false,
            isMemberExtension: Bool = false,
            receiverOwnerFQName: [InternedString]? = nil,
            valueParameterIsVararg: [Bool] = [],
            valueParameterAllowsNonLocalReturn: [Bool] = [],
            valueParameterHasDefaultValues: [Bool] = [],
            valueParameterCallsInPlaceKinds: [InvocationKind?] = [],
            contractImplicationEffects: [ContractImplicationEffect] = [],
            canThrow: Bool = false,
            valueParameterNames: [String] = [],
            reifiedTypeParameterIndices: Set<Int> = [],
            typeSignature: String? = nil,
            typeParameterUpperBoundsSignatures: [[String]] = [],
            callableTypeParameterSignatures: [String] = [],
            inputOnlyTypeParameterIndices: Set<Int> = [],
            defaultStubExternalLinkName: String? = nil,
            externalLinkName: String? = nil,
            declaredFieldCount: Int? = nil,
        declaredInstanceSizeWords: Int? = nil,
        declaredVtableSize: Int? = nil,
        declaredItableSize: Int? = nil,
        superFQName: [InternedString]? = nil,
        superFQNames: [[InternedString]]? = nil,
            companionObjectFQName: [InternedString]? = nil,
            fieldOffsets: [ImportedFieldOffsetEntry] = [],
            vtableSlots: [ImportedVTableSlotEntry] = [],
        itableSlots: [ImportedITableSlotEntry] = [],
        objectInitializerLinkName: String? = nil,
        companionInitializerLinkName: String? = nil,
        objectLazyInitializerLinkName: String? = nil,
        enumStaticInitLinkName: String? = nil,
        isDataClass: Bool = false,
        isOpenClass: Bool = false,
        modality: MetadataModality = .final,
        isSealedClass: Bool = false,
        isFunInterface: Bool = false,
            isValueClass: Bool = false,
            isExpect: Bool = false,
            isActual: Bool = false,
            valueClassUnderlyingTypeSig: String? = nil,
            annotations: [MetadataAnnotationRecord] = [],
            sealedSubclassFQNames: [[InternedString]] = [],
            propertyReceiverTypeSignature: String? = nil,
            propertyGetterExternalLinkName: String? = nil,
            propertySetterExternalLinkName: String? = nil,
            abiReturnTypeSignature: String? = nil,
            propertyGetterAbiReturnTypeSignature: String? = nil,
            isMutable: Bool = false,
        nominalTypeParametersSignature: String? = nil,
        ownerNominalTypeParametersSignature: String? = nil,
        nominalSupertypeSignatures: [String] = [],
            constValueLiteral: String? = nil,
            nominalTypeParameters: String? = nil
        ) {
            self.kind = kind
            self.visibility = visibility
            self.mangledName = mangledName
            self.fqName = fqName
            self.arity = arity
            self.isSuspend = isSuspend
            self.isInline = isInline
            self.isOperator = isOperator
            self.isInfix = isInfix
            self.isOverride = isOverride
            self.isMemberExtension = isMemberExtension
            self.receiverOwnerFQName = receiverOwnerFQName
            self.valueParameterIsVararg = valueParameterIsVararg
            self.valueParameterAllowsNonLocalReturn = valueParameterAllowsNonLocalReturn
            self.valueParameterHasDefaultValues = valueParameterHasDefaultValues
            self.valueParameterCallsInPlaceKinds = valueParameterCallsInPlaceKinds
            self.contractImplicationEffects = contractImplicationEffects
            self.canThrow = canThrow
            self.valueParameterNames = valueParameterNames
            self.reifiedTypeParameterIndices = reifiedTypeParameterIndices
            self.typeSignature = typeSignature
            self.typeParameterUpperBoundsSignatures = typeParameterUpperBoundsSignatures
            self.callableTypeParameterSignatures = callableTypeParameterSignatures
            self.inputOnlyTypeParameterIndices = inputOnlyTypeParameterIndices
            self.defaultStubExternalLinkName = defaultStubExternalLinkName
            self.externalLinkName = externalLinkName
            self.declaredFieldCount = declaredFieldCount
            self.declaredInstanceSizeWords = declaredInstanceSizeWords
        self.declaredVtableSize = declaredVtableSize
        self.declaredItableSize = declaredItableSize
        self.superFQName = superFQName
        self.superFQNames = superFQNames
            self.companionObjectFQName = companionObjectFQName
            self.fieldOffsets = fieldOffsets
            self.vtableSlots = vtableSlots
            self.itableSlots = itableSlots
        self.objectInitializerLinkName = objectInitializerLinkName
        self.companionInitializerLinkName = companionInitializerLinkName
        self.objectLazyInitializerLinkName = objectLazyInitializerLinkName
        self.enumStaticInitLinkName = enumStaticInitLinkName
        self.isDataClass = isDataClass
        self.isOpenClass = isOpenClass
        self.modality = modality
        self.isSealedClass = isSealedClass
        self.isFunInterface = isFunInterface
            self.isValueClass = isValueClass
            self.isExpect = isExpect
            self.isActual = isActual
            self.valueClassUnderlyingTypeSig = valueClassUnderlyingTypeSig
            self.annotations = annotations
            self.sealedSubclassFQNames = sealedSubclassFQNames
            self.propertyReceiverTypeSignature = propertyReceiverTypeSignature
            self.propertyGetterExternalLinkName = propertyGetterExternalLinkName
            self.propertySetterExternalLinkName = propertySetterExternalLinkName
            self.abiReturnTypeSignature = abiReturnTypeSignature
            self.propertyGetterAbiReturnTypeSignature = propertyGetterAbiReturnTypeSignature
            self.isMutable = isMutable
        self.nominalTypeParametersSignature = nominalTypeParametersSignature
        self.ownerNominalTypeParametersSignature = ownerNominalTypeParametersSignature
            self.nominalSupertypeSignatures = nominalSupertypeSignatures
            self.constValueLiteral = constValueLiteral
            self.nominalTypeParameters = nominalTypeParameters
        }
    }

    final class ImportedLibraryBinding {
        private(set) var record: ImportedLibrarySymbolRecord
        let symbol: SymbolID
        let metadataPath: String
        let inlineKIRDir: String?
        let isStdlibArtifact: Bool
        private let materializeBody: (() -> ImportedLibrarySymbolRecord?)?
        private(set) var isMaterialized: Bool

        init(
            record: ImportedLibrarySymbolRecord,
            symbol: SymbolID,
            metadataPath: String,
            inlineKIRDir: String?,
            isStdlibArtifact: Bool,
            materializeBody: (() -> ImportedLibrarySymbolRecord?)? = nil
        ) {
            self.record = record
            self.symbol = symbol
            self.metadataPath = metadataPath
            self.inlineKIRDir = inlineKIRDir
            self.isStdlibArtifact = isStdlibArtifact
            self.materializeBody = materializeBody
            self.isMaterialized = materializeBody == nil
        }

        /// Whether this binding came from a v2 index and its `.kir` inline
        /// body should stay unparsed until lowering demands it.
        var defersInlineBodyImport: Bool {
            materializeBody != nil
        }

        @discardableResult
        func materialize() -> ImportedLibrarySymbolRecord {
            guard !isMaterialized else { return record }
            if let materialized = materializeBody?() {
                record = materialized
            }
            isMaterialized = true
            return record
        }
    }
}

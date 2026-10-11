import Foundation

package enum MetadataModality: String {
    case final
    case open
    case abstract
}

// MARK: - Shared Metadata Record

/// Unified metadata record used by both export (MetadataEncoder) and import (MetadataDecoder).
/// This is the single source of truth for what information survives the metadata round-trip.
package struct MetadataRecord {
    package let kind: SymbolKind
    package let visibility: Visibility
    let mangledName: String
    package let fqName: String
    package let arity: Int
    package let isSuspend: Bool
    package let isInline: Bool
    package let isOperator: Bool
    package let isInfix: Bool
    /// Whether the member overrides a supertype member (`override` keyword).
    package let isOverride: Bool
    package let isMemberExtension: Bool
    /// Nominal owner of a callable/property receiver. The indexed metadata
    /// path keeps this compact routing key available without decoding the
    /// declaration body, so synthetic stdlib overlap guards can run eagerly.
    let receiverOwnerFQName: String?
    let typeSignature: String?
    /// Upper-bound type signatures for callable type parameters, in declaration order.
    /// Empty entries preserve alignment when only a later type parameter is bounded.
    package let typeParameterUpperBoundsSignatures: [[String]]
    /// Type parameter references of a callable in declaration order, encoded as
    /// `T<rawID>` tokens (e.g. `T5023`) matching the encoding used inside type
    /// signatures. For member callables this is the full list, including the
    /// leading owner (class) type parameters. It preserves the declared order
    /// for parameters that never appear in the decoded signature ("phantom"
    /// parameters referenced only inside the body via explicit type arguments
    /// to other generic calls) and disambiguates parameters across overloads
    /// that share one FQ name.
    package let callableTypeParameterSignatures: [String]
    package let inputOnlyTypeParameterIndices: Set<Int>
    /// Per-parameter vararg flags for function/constructor signatures.
    package let valueParameterIsVararg: [Bool]
    /// Per-parameter flags indicating whether a function-type argument may
    /// contain a non-local return when the callable is inline-expanded.
    package let valueParameterAllowsNonLocalReturn: [Bool]
    /// STDLIB-592: per-parameter `contract { callsInPlace(param, kind) }` effect,
    /// `nil` where the parameter has none. Lets definite-assignment analysis see
    /// bundled-stdlib contracts (e.g. `run`/`let`/`apply`/`also`/`with`) even when
    /// the stdlib is loaded from a precompiled `.kklib` rather than re-typechecked
    /// from source, since `recordContractEffects` never runs against a decoded
    /// symbol's (nonexistent) AST body.
    package let valueParameterCallsInPlaceKinds: [InvocationKind?]
    package let contractImplicationEffects: [ContractImplicationEffect]
    /// Per-parameter default-value flags for function/constructor signatures.
    package let valueParameterHasDefaultValues: [Bool]
    /// Whether the function/constructor is declared `throws`.
    package let canThrow: Bool
    /// Resolved names of value parameters, in declaration order, used for
    /// named-argument resolution on imported functions.
    package let valueParameterNames: [String]
    /// Indices of reified type parameters, in declaration order, so that
    /// call sites append the correct runtime type-token arguments for inline
    /// functions imported from a precompiled stdlib artifact.
    package let reifiedTypeParameterIndices: Set<Int>
    /// Link name of the precompiled default-argument stub (e.g. `foo$default`).
    let defaultStubExternalLinkName: String?
    let externalLinkName: String?
    package let declaredFieldCount: Int?
    package let declaredInstanceSizeWords: Int?
    let declaredVtableSize: Int?
    let declaredItableSize: Int?
    package let superFQName: String?
    package let companionObjectFQName: String?
    let fieldOffsets: String?
    let vtableSlots: String?
    let itableSlots: String?
    /// Link name of the precompiled top-level object initializer (e.g. `__object_init_*`).
    let objectInitializerLinkName: String?
    /// Link name of the precompiled companion object initializer (e.g. `__companion_init_*`).
    let companionInitializerLinkName: String?
    /// Link name of the guarded object/companion body initializer.
    let objectLazyInitializerLinkName: String?
    /// Link name of the precompiled enum static initializer (e.g. `__enum_static_init_*`).
    package let enumStaticInitLinkName: String?

    // P5-74: data class flag
    package let isDataClass: Bool

    /// Whether a nominal declaration is explicitly open and may be subclassed.
    /// This must survive library metadata import; Kotlin classes are final by default.
    package let isOpenClass: Bool
    /// Inner classes require an enclosing instance even when their public constructor arity is zero.
    package let isInnerClass: Bool
    /// Declaration modality for classes and members. Final is omitted from the
    /// wire format so older artifacts remain compact and decode as final.
    package let modality: MetadataModality

    // P5-74: sealed class flag
    package let isSealedClass: Bool

    // STDLIB-SHARED-003: fun interface flag for SAM-constructor resolution
    package let isFunInterface: Bool

    // P5-86: annotation metadata
    let annotations: [MetadataAnnotationRecord]

    // P5-75: value class flag
    package let isValueClass: Bool

    // P5-75: value class underlying type signature (e.g. "I" for Int)
    let valueClassUnderlyingTypeSig: String?

    // P5-78: sealed subclass FQ names for cross-module exhaustiveness
    let sealedSubclassFQNames: [String]

    // MPP-001: expect/actual declaration flags
    let isExpect: Bool
    let isActual: Bool

    /// Receiver type signature for extension properties; nil for non-extension properties.
    let propertyReceiverTypeSignature: String?
    /// Link name of the precompiled getter accessor for extension properties.
    let propertyGetterExternalLinkName: String?
    /// Link name of the precompiled setter accessor for `var` properties.
    let propertySetterExternalLinkName: String?
    /// ABI return type signature for functions whose compiled return type differs
    /// from the source-level signature (e.g. raw `Int` string handles).
    let abiReturnTypeSignature: String?
    /// ABI return type signature for extension property getters when it differs
    /// from the property's source type.
    let propertyGetterAbiReturnTypeSignature: String?
    /// True for `var` properties/fields.
    package let isMutable: Bool
    /// Self type signature of a generic nominal declaration, carrying its type
    /// parameters and their declared variance (e.g.
    /// `Lkotlinx.coroutines.flow.SharedFlow<O<T8150>>;`).
    let nominalTypeParametersSignature: String?
    /// Type signatures of the generic direct supertypes of a nominal
    /// declaration, with the child's type parameters substituted in (e.g.
    /// `Lkotlinx.coroutines.flow.SharedFlow<T8154>;`).
    let nominalSupertypeSignatures: [String]
    /// Encoded compile-time constant value of a `const val` property, so
    /// consumers can inline it instead of reading an uninitialized global slot
    /// (a precompiled library has no `main` to run top-level initializers).
    let constValueLiteral: String?
    /// Declaration-order type parameters of a nominal type, encoded as
    /// `<typeSignature>:<variance>` pairs (e.g. `T5023:i`), so consumers can
    /// restore the generic arity used by constructor/member resolution.
    let nominalTypeParameters: String?

    init(
        kind: SymbolKind,
        visibility: Visibility = .public,
        mangledName: String = "",
        fqName: String = "",
        arity: Int = 0,
        isSuspend: Bool = false,
        isInline: Bool = false,
        isOperator: Bool = false,
        isInfix: Bool = false,
        isOverride: Bool = false,
        isMemberExtension: Bool = false,
        receiverOwnerFQName: String? = nil,
        typeSignature: String? = nil,
        typeParameterUpperBoundsSignatures: [[String]] = [],
        callableTypeParameterSignatures: [String] = [],
        inputOnlyTypeParameterIndices: Set<Int> = [],
        valueParameterIsVararg: [Bool] = [],
        valueParameterAllowsNonLocalReturn: [Bool] = [],
        valueParameterHasDefaultValues: [Bool] = [],
        valueParameterCallsInPlaceKinds: [InvocationKind?] = [],
        contractImplicationEffects: [ContractImplicationEffect] = [],
        canThrow: Bool = false,
        valueParameterNames: [String] = [],
        reifiedTypeParameterIndices: Set<Int> = [],
        defaultStubExternalLinkName: String? = nil,
        externalLinkName: String? = nil,
        declaredFieldCount: Int? = nil,
        declaredInstanceSizeWords: Int? = nil,
        declaredVtableSize: Int? = nil,
        declaredItableSize: Int? = nil,
        superFQName: String? = nil,
        companionObjectFQName: String? = nil,
        fieldOffsets: String? = nil,
        vtableSlots: String? = nil,
        itableSlots: String? = nil,
        objectInitializerLinkName: String? = nil,
        companionInitializerLinkName: String? = nil,
        objectLazyInitializerLinkName: String? = nil,
        enumStaticInitLinkName: String? = nil,
        isDataClass: Bool = false,
        isOpenClass: Bool = false,
        isInnerClass: Bool = false,
        modality: MetadataModality = .final,
        isSealedClass: Bool = false,
        isFunInterface: Bool = false,
        annotations: [MetadataAnnotationRecord] = [],
        isValueClass: Bool = false,
        valueClassUnderlyingTypeSig: String? = nil,
        sealedSubclassFQNames: [String] = [],
        isExpect: Bool = false,
        isActual: Bool = false,
        propertyReceiverTypeSignature: String? = nil,
        propertyGetterExternalLinkName: String? = nil,
        propertySetterExternalLinkName: String? = nil,
        abiReturnTypeSignature: String? = nil,
        propertyGetterAbiReturnTypeSignature: String? = nil,
        isMutable: Bool = false,
        nominalTypeParametersSignature: String? = nil,
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
        self.typeSignature = typeSignature
        self.typeParameterUpperBoundsSignatures = typeParameterUpperBoundsSignatures
        self.callableTypeParameterSignatures = callableTypeParameterSignatures
        self.inputOnlyTypeParameterIndices = inputOnlyTypeParameterIndices
        self.valueParameterIsVararg = valueParameterIsVararg
        self.valueParameterAllowsNonLocalReturn = valueParameterAllowsNonLocalReturn
        self.valueParameterHasDefaultValues = valueParameterHasDefaultValues
        self.valueParameterCallsInPlaceKinds = valueParameterCallsInPlaceKinds
        self.contractImplicationEffects = contractImplicationEffects
        self.canThrow = canThrow
        self.valueParameterNames = valueParameterNames
        self.reifiedTypeParameterIndices = reifiedTypeParameterIndices
        self.defaultStubExternalLinkName = defaultStubExternalLinkName
        self.externalLinkName = externalLinkName
        self.declaredFieldCount = declaredFieldCount
        self.declaredInstanceSizeWords = declaredInstanceSizeWords
        self.declaredVtableSize = declaredVtableSize
        self.declaredItableSize = declaredItableSize
        self.superFQName = superFQName
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
        self.isInnerClass = isInnerClass
        self.modality = modality
        self.isSealedClass = isSealedClass
        self.isFunInterface = isFunInterface
        self.annotations = annotations
        self.isValueClass = isValueClass
        self.valueClassUnderlyingTypeSig = valueClassUnderlyingTypeSig
        self.sealedSubclassFQNames = sealedSubclassFQNames
        self.isExpect = isExpect
        self.isActual = isActual
        self.propertyReceiverTypeSignature = propertyReceiverTypeSignature
        self.propertyGetterExternalLinkName = propertyGetterExternalLinkName
        self.propertySetterExternalLinkName = propertySetterExternalLinkName
        self.abiReturnTypeSignature = abiReturnTypeSignature
        self.propertyGetterAbiReturnTypeSignature = propertyGetterAbiReturnTypeSignature
        self.isMutable = isMutable
        self.nominalTypeParametersSignature = nominalTypeParametersSignature
        self.nominalSupertypeSignatures = nominalSupertypeSignatures
        self.constValueLiteral = constValueLiteral
        self.nominalTypeParameters = nominalTypeParameters
    }
}

/// Annotation metadata that survives the export/import round-trip (P5-86).
public struct MetadataAnnotationRecord: Equatable {
    /// Fully-qualified name of the annotation class (e.g. "kotlin.Deprecated").
    public let annotationFQName: String
    /// Serialized argument values.
    public let arguments: [String]
    /// Optional use-site target (get, set, field, param, etc.).
    public let useSiteTarget: String?

    public init(
        annotationFQName: String,
        arguments: [String] = [],
        useSiteTarget: String? = nil
    ) {
        self.annotationFQName = annotationFQName
        self.arguments = arguments
        self.useSiteTarget = useSiteTarget
    }
}

/// One entry in the v2 metadata index. Offsets and lengths are measured in
/// UTF-8 bytes relative to the beginning of the body section.
struct MetadataIndexEntry {
    let offset: Int
    let length: Int
    let record: MetadataRecord
}

/// Lazily reads v2 metadata records from the body section of `metadata.bin`.
/// The index is parsed at library discovery time; the body is sliced only when
/// a semantic query needs the corresponding declaration.
final class IndexedMetadataFile {
    let entries: [MetadataIndexEntry]

    private let data: Data
    private let bodyStart: Int
    private var decodedRecords: [Int: MetadataRecord] = [:]

    init?(data: Data) {
        self.data = data
        var cursor = 0
        let bytes = [UInt8](data)

        func readLine() -> String? {
            guard cursor <= bytes.count else { return nil }
            let start = cursor
            while cursor < bytes.count, bytes[cursor] != 0x0A {
                cursor += 1
            }
            let line = String(decoding: bytes[start ..< cursor], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if cursor < bytes.count {
                cursor += 1
            }
            return line
        }

        guard readLine() == "kklib-metadata-v2" else { return nil }
        guard let recordsLine = readLine(), recordsLine.hasPrefix("records=") else { return nil }
        guard Int(recordsLine.dropFirst("records=".count)) != nil else { return nil }
        guard readLine() == "index" else { return nil }

        var parsedEntries: [MetadataIndexEntry] = []
        let decoder = MetadataDecoder()
        while let line = readLine(), line != "body" {
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3,
                  let offset = Int(fields[0]),
                  let length = Int(fields[1]),
                  offset >= 0,
                  length > 0,
                  let record = decoder.decode("symbols=1\n\(fields[2])\n").first
            else {
                return nil
            }
            parsedEntries.append(MetadataIndexEntry(offset: offset, length: length, record: record))
        }

        guard cursor <= bytes.count else { return nil }
        self.bodyStart = cursor
        self.entries = parsedEntries
    }

    func record(for entry: MetadataIndexEntry) -> MetadataRecord? {
        if let cached = decodedRecords[entry.offset] {
            return cached
        }
        let start = bodyStart + entry.offset
        let end = start + entry.length
        guard start >= bodyStart, end <= data.count else { return nil }
        let body = data.subdata(in: start ..< end)
        guard let line = String(data: body, encoding: .utf8) else { return nil }
        let record = MetadataDecoder().decode("symbols=1\n\(line)\n").first
        if let record {
            decodedRecords[entry.offset] = record
        }
        return record
    }
}

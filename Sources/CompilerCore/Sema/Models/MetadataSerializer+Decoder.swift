import Foundation

// MARK: - MetadataDecoder (Import)

/// Decodes the text-based metadata format into `[MetadataRecord]`.
/// This replaces the ad-hoc parsing previously done in DataFlow/LibraryMetadataParsing.swift.
final class MetadataDecoder {
    init() {}

    /// Parse text content into metadata records.
    func decode(_ content: String) -> [MetadataRecord] {
        if content.hasPrefix("kklib-metadata-v2\n"),
           let indexed = IndexedMetadataFile(data: Data(content.utf8))
        {
            return indexed.entries.compactMap { indexed.record(for: $0) }
        }
        var records: [MetadataRecord] = []
        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("symbols=") {
                continue
            }
            let parts = line.split(separator: " ").map(String.init)
            guard let kindToken = parts.first,
                  let kind = symbolKindFromMetadata(kindToken)
            else {
                continue
            }
            let mangledName = parts.count > 1 ? parts[1] : ""

            var rec = MutableMetadataRecord()

            for part in parts.dropFirst() {
                guard let separatorIndex = part.firstIndex(of: "=") else {
                    continue
                }
                let key = String(part[..<separatorIndex])
                let value = String(part[part.index(after: separatorIndex)...])
                applyKeyValuePart(key: key, value: value, into: &rec)
            }

            // Backward-compatible schema gate:
            // - records without schema are treated as legacy v1
            // - only explicitly non-v1 schema versions are rejected
            guard !rec.fqName.isEmpty else {
                continue
            }
            if let schemaVersion = rec.schemaVersion, schemaVersion != "v1" {
                continue
            }

            records.append(MetadataRecord(
                kind: kind,
                visibility: rec.visibility,
                mangledName: mangledName,
                fqName: rec.fqName,
                arity: rec.arity,
                isSuspend: rec.isSuspend,
                isInline: rec.isInline,
                isOperator: rec.isOperator,
                isInfix: rec.isInfix,
                isOverride: rec.isOverride,
                isMemberExtension: rec.isMemberExtension,
                receiverOwnerFQName: rec.receiverOwnerFQName,
                typeSignature: rec.typeSignature,
                typeParameterUpperBoundsSignatures: rec.typeParameterUpperBoundsSignatures,
                callableTypeParameterSignatures: rec.callableTypeParameterSignatures,
                inputOnlyTypeParameterIndices: rec.inputOnlyTypeParameterIndices,
                valueParameterIsVararg: rec.valueParameterIsVararg,
                valueParameterAllowsNonLocalReturn: rec.valueParameterAllowsNonLocalReturn,
                valueParameterHasDefaultValues: rec.valueParameterHasDefaultValues,
                valueParameterCallsInPlaceKinds: rec.valueParameterCallsInPlaceKinds,
                contractImplicationEffects: rec.contractImplicationEffects,
                canThrow: rec.canThrow,
                valueParameterNames: rec.valueParameterNames,
                reifiedTypeParameterIndices: rec.reifiedTypeParameterIndices,
                defaultStubExternalLinkName: rec.defaultStubExternalLinkName,
                externalLinkName: rec.externalLinkName,
                declaredFieldCount: rec.declaredFieldCount,
                declaredInstanceSizeWords: rec.declaredInstanceSizeWords,
                declaredVtableSize: rec.declaredVtableSize,
                declaredItableSize: rec.declaredItableSize,
                superFQName: rec.superFQName,
                companionObjectFQName: rec.companionObjectFQName,
                fieldOffsets: rec.fieldOffsets,
                vtableSlots: rec.vtableSlots,
                itableSlots: rec.itableSlots,
                objectInitializerLinkName: rec.objectInitializerLinkName,
                companionInitializerLinkName: rec.companionInitializerLinkName,
                objectLazyInitializerLinkName: rec.objectLazyInitializerLinkName,
                enumStaticInitLinkName: rec.enumStaticInitLinkName,
                isDataClass: rec.isDataClass,
                isOpenClass: rec.isOpenClass,
                modality: rec.modality,
                isSealedClass: rec.isSealedClass,
                isFunInterface: rec.isFunInterface,
                annotations: rec.annotations,
                isValueClass: rec.isValueClass,
                valueClassUnderlyingTypeSig: rec.valueClassUnderlyingTypeSig,
                sealedSubclassFQNames: rec.sealedSubclassFQNames,
                isExpect: rec.isExpect,
                isActual: rec.isActual,
                propertyReceiverTypeSignature: rec.propertyReceiverTypeSignature,
                propertyGetterExternalLinkName: rec.propertyGetterExternalLinkName,
                propertySetterExternalLinkName: rec.propertySetterExternalLinkName,
                abiReturnTypeSignature: rec.abiReturnTypeSignature,
                propertyGetterAbiReturnTypeSignature: rec.propertyGetterAbiReturnTypeSignature,
                isMutable: rec.isMutable,
                nominalTypeParametersSignature: rec.nominalTypeParametersSignature,
                nominalSupertypeSignatures: rec.nominalSupertypeSignatures,
                constValueLiteral: rec.constValueLiteral,
                nominalTypeParameters: rec.nominalTypeParameters
            ))
        }
        return records
    }

    // MARK: - Key-Value Parsing

    /// Mutable accumulator used while parsing a single metadata line.
    private struct MutableMetadataRecord {
        var fqName: String = ""
        var visibility: Visibility = .public
        var arity: Int = 0
        var isSuspend: Bool = false
        var isInline: Bool = false
        var isOperator: Bool = false
        var isInfix: Bool = false
        var isOverride: Bool = false
        var isMemberExtension: Bool = false
        var receiverOwnerFQName: String?
        var typeSignature: String?
        var callableTypeParameterSignatures: [String] = []
        var inputOnlyTypeParameterIndices: Set<Int> = []
        var valueParameterIsVararg: [Bool] = []
        var valueParameterAllowsNonLocalReturn: [Bool] = []
        var valueParameterHasDefaultValues: [Bool] = []
        var valueParameterCallsInPlaceKinds: [InvocationKind?] = []
        var contractImplicationEffects: [ContractImplicationEffect] = []
        var canThrow: Bool = false
        var valueParameterNames: [String] = []
        var reifiedTypeParameterIndices: Set<Int> = []
        var defaultStubExternalLinkName: String?
        var externalLinkName: String?
        var declaredFieldCount: Int?
        var declaredInstanceSizeWords: Int?
        var declaredVtableSize: Int?
        var declaredItableSize: Int?
        var superFQName: String?
        var companionObjectFQName: String?
        var fieldOffsets: String?
        var vtableSlots: String?
        var itableSlots: String?
        var objectInitializerLinkName: String?
        var companionInitializerLinkName: String?
        var objectLazyInitializerLinkName: String?
        var enumStaticInitLinkName: String?
        var isDataClass: Bool = false
        var isOpenClass: Bool = false
        var modality: MetadataModality = .final
        var isSealedClass: Bool = false
        var isFunInterface: Bool = false
        var isValueClass: Bool = false
        var valueClassUnderlyingTypeSig: String?
        var annotations: [MetadataAnnotationRecord] = []
        var sealedSubclassFQNames: [String] = []
        var isExpect: Bool = false
        var isActual: Bool = false
        var propertyReceiverTypeSignature: String?
        var propertyGetterExternalLinkName: String?
        var propertySetterExternalLinkName: String?
        var abiReturnTypeSignature: String?
        var propertyGetterAbiReturnTypeSignature: String?
        var isMutable: Bool = false
        var nominalTypeParametersSignature: String?
        var nominalSupertypeSignatures: [String] = []
        var constValueLiteral: String?
        var nominalTypeParameters: String?
        var typeParameterUpperBoundsSignatures: [[String]] = []
        var schemaVersion: String?
    }

    private func applyKeyValuePart(key: String, value: String, into record: inout MutableMetadataRecord) {
        switch key {
        case "fq":
            record.fqName = value
        case "visibility":
            record.visibility = switch value {
            case "public": .public
            case "private": .private
            case "internal": .internal
            case "protected": .protected
            default: .private
            }
        case "arity":
            record.arity = Int(value) ?? Int.max
        case "suspend":
            record.isSuspend = value == "1" || value == "true"
        case "inline":
            record.isInline = value == "1" || value == "true"
        case "infix":
            record.isInfix = value == "1" || value == "true"
        case "operator":
            record.isOperator = value == "1" || value == "true"
        case "override":
            record.isOverride = value == "1" || value == "true"
        case "memberExtension":
            record.isMemberExtension = value == "1" || value == "true"
        case "receiverFq":
            record.receiverOwnerFQName = value.isEmpty ? nil : value
        case "vararg":
            record.valueParameterIsVararg = value.map { $0 == "1" }
        case "nonLocal":
            record.valueParameterAllowsNonLocalReturn = value.map { $0 == "1" }
        case "default":
            record.valueParameterHasDefaultValues = value.map { $0 == "1" }
        case "callsInPlace":
            record.valueParameterCallsInPlaceKinds = value.map { char -> InvocationKind? in
                switch char {
                case "M": .atMostOnce
                case "A": .atLeastOnce
                case "E": .exactlyOnce
                case "U": .unknown
                default: nil
                }
            }
        case "contractImplies":
            record.contractImplicationEffects = value.split(separator: ",").compactMap { item in
                let parts = item.split(separator: ":")
                guard (parts.count == 3 || parts.count == 4), let index = Int(parts[0]), index >= 0,
                      let result = ContractReturnCondition(rawValue: String(parts[1])),
                      let condition = ContractArgumentCondition(rawValue: String(parts[2])) else { return nil }
                let signature = parts.count == 4 ? Data(base64Encoded: String(parts[3])).flatMap { String(data: $0, encoding: .utf8) } : nil
                guard condition != .isType || signature != nil else { return nil }
                return ContractImplicationEffect(parameterIndex: index, returnCondition: result, argumentCondition: condition, targetTypeSignature: signature)
            }
        case "canThrow":
            record.canThrow = value == "1" || value == "true"
        case "paramNames":
            record.valueParameterNames = value.split(separator: ",").map(String.init)
        case "reified":
            record.reifiedTypeParameterIndices = Set(
                value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            )
        case "defaultLink":
            record.defaultStubExternalLinkName = value.isEmpty ? nil : value
        case "sig":
            record.typeSignature = value.isEmpty ? nil : value
        case "typeBounds":
            record.typeParameterUpperBoundsSignatures = decodeMetadataTypeParameterUpperBounds(value)
        case "callTParams":
            record.callableTypeParameterSignatures = value.split(separator: ",").map(String.init)
        case "inputOnlyTParams":
            record.inputOnlyTypeParameterIndices = Set(value.split(separator: ",").compactMap { Int($0) })
        case "link":
            record.externalLinkName = value.isEmpty ? nil : value
        case "fields":
            record.declaredFieldCount = Int(value)
        case "layoutWords":
            record.declaredInstanceSizeWords = Int(value)
        case "vtable":
            record.declaredVtableSize = Int(value)
        case "itable":
            record.declaredItableSize = Int(value)
        case "superFq":
            record.superFQName = value.isEmpty ? nil : value
        case "typeParamsSig":
            record.nominalTypeParametersSignature = value.isEmpty ? nil : value
        case "superSigs":
            record.nominalSupertypeSignatures = value.split(separator: "|").map(String.init)
        case "companionFq":
            record.companionObjectFQName = value.isEmpty ? nil : value
        case "fieldOffsets":
            record.fieldOffsets = value.isEmpty ? nil : value
        case "vtableSlots":
            record.vtableSlots = value.isEmpty ? nil : value
        case "itableSlots":
            record.itableSlots = value.isEmpty ? nil : value
        case "typeParams":
            record.nominalTypeParameters = value.isEmpty ? nil : value
        case "objectInitLink":
            record.objectInitializerLinkName = value.isEmpty ? nil : value
        case "companionInitLink":
            record.companionInitializerLinkName = value.isEmpty ? nil : value
        case "objectLazyInitLink":
            record.objectLazyInitializerLinkName = value.isEmpty ? nil : value
        case "enumStaticInitLink":
            record.enumStaticInitLinkName = value.isEmpty ? nil : value
        case "dataClass":
            record.isDataClass = value == "1" || value == "true"
        case "openClass":
            record.isOpenClass = value == "1" || value == "true"
        case "modality":
            record.modality = MetadataModality(rawValue: value) ?? .final
        case "sealedClass":
            record.isSealedClass = value == "1" || value == "true"
        case "funInterface":
            record.isFunInterface = value == "1" || value == "true"
        case "valueClass":
            record.isValueClass = value == "1" || value == "true"
        case "valueUnderlying":
            record.valueClassUnderlyingTypeSig = value.isEmpty ? nil : value
        case "sealedSubs":
            record.sealedSubclassFQNames = value.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        case "annotations":
            record.annotations = decodeAnnotations(value)
        case "expect":
            record.isExpect = value == "1" || value == "true"
        case "actual":
            record.isActual = value == "1" || value == "true"
        case "recv":
            record.propertyReceiverTypeSignature = value.isEmpty ? nil : value
        case "getterLink":
            record.propertyGetterExternalLinkName = value.isEmpty ? nil : value
        case "setterLink":
            record.propertySetterExternalLinkName = value.isEmpty ? nil : value
        case "getterAbiSig":
            record.propertyGetterAbiReturnTypeSignature = value.isEmpty ? nil : value
        case "mutable":
            record.isMutable = value == "1" || value == "true"
        case "const":
            record.constValueLiteral = value.isEmpty ? nil : value
        case "abiSig":
            record.abiReturnTypeSignature = value.isEmpty ? nil : value
        case "schema":
            record.schemaVersion = value
        default:
            break
        }
    }

    // MARK: - Annotation Decoding

    private func decodeAnnotations(_ value: String) -> [MetadataAnnotationRecord] {
        guard !value.isEmpty else {
            return []
        }
        return value.split(separator: ";", omittingEmptySubsequences: true).compactMap { entry in
            decodeAnnotation(String(entry))
        }
    }

    private func decodeAnnotation(_ entry: String) -> MetadataAnnotationRecord? {
        let parts = entry.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard let annotationFQName = parts.first, !annotationFQName.isEmpty else {
            return nil
        }
        var useSiteTarget: String?
        var arguments: [String] = []
        for part in parts.dropFirst() {
            if part.hasPrefix("target:") {
                useSiteTarget = String(part.dropFirst("target:".count))
            } else if part.hasPrefix("args:") {
                let argsStr = String(part.dropFirst("args:".count))
                arguments = argsStr.split(separator: ",", omittingEmptySubsequences: false).compactMap { b64 in
                    guard let data = Data(base64Encoded: String(b64)) else {
                        return nil
                    }
                    return String(data: data, encoding: .utf8)
                }
            }
        }
        return MetadataAnnotationRecord(
            annotationFQName: annotationFQName,
            arguments: arguments,
            useSiteTarget: useSiteTarget
        )
    }

    // MARK: - Symbol Kind Mapping

    func symbolKindFromMetadata(_ token: String) -> SymbolKind? {
        symbolKindFromMetadataToken(token)
    }
}

private func decodeMetadataTypeParameterUpperBounds(_ value: String) -> [[String]] {
    value.split(separator: "|", omittingEmptySubsequences: false).map { group in
        guard !group.isEmpty else { return [] }
        return group.split(separator: ",", omittingEmptySubsequences: false).compactMap { encoded in
            guard let data = Data(base64Encoded: String(encoded)),
                  let decoded = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            return decoded
        }
    }
}

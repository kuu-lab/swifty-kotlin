import Foundation

final class MetadataDecoder {
    init() {}

    /// Binary v3 and legacy text share the same full-record body decoder.
    func decode(_ data: Data) -> [MetadataRecord] {
        if data.starts(with: CompactMetadataIndex.magic) {
            guard let indexed = IndexedMetadataFile(data: data) else { return [] }
            return indexed.entries.compactMap { indexed.record(for: $0) }
        }
        guard let content = String(data: data, encoding: .utf8) else { return [] }
        return decode(content)
    }

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

            records.append(makeRecord(kind: kind, mangledName: mangledName, rec: rec))
        }
        return records
    }

    /// Parse one compact index record directly from its UTF-8 storage. This
    /// avoids a temporary header, Unicode line splitting, and a token array
    /// for every declaration while sharing the legacy field/default semantics.
    func decodeIndexRecordLine(_ bytes: UnsafeBufferPointer<UInt8>) -> MetadataRecord? {
        guard String(bytes: bytes, encoding: .utf8) != nil else { return nil }
        var cursor = 0
        var end = bytes.count
        func isWhitespace(_ byte: UInt8) -> Bool {
            byte == 0x20 || (0x09 ... 0x0D).contains(byte)
        }
        while cursor < end, isWhitespace(bytes[cursor]) { cursor += 1 }
        while end > cursor, isWhitespace(bytes[end - 1]) { end -= 1 }
        if cursor < end, bytes[cursor] >= 0x80 || bytes[end - 1] >= 0x80 {
            // Preserve Unicode edge trimming for hand-written records.
            return decode(String(decoding: UnsafeBufferPointer(rebasing: bytes[cursor ..< end]), as: UTF8.self)).first
        }
        func nextToken() -> Range<Int>? {
            while cursor < end, bytes[cursor] == 0x20 { cursor += 1 }
            guard cursor < end else { return nil }
            let start = cursor
            while cursor < end, bytes[cursor] != 0x20 { cursor += 1 }
            return start ..< cursor
        }
        func string(_ range: Range<Int>) -> String {
            String(decoding: UnsafeBufferPointer(rebasing: bytes[range]), as: UTF8.self)
        }
        guard let kindRange = nextToken(), let kind = symbolKindFromMetadata(string(kindRange)) else {
            return nil
        }
        var mangledName = ""
        var isFirstPart = true
        var rec = MutableMetadataRecord()
        while let range = nextToken() {
            if isFirstPart {
                mangledName = string(range)
                isFirstPart = false
            }
            var separator = range.lowerBound
            while separator < range.upperBound, bytes[separator] != 0x3D { separator += 1 }
            guard separator < range.upperBound else { continue }
            applyKeyValuePart(
                key: string(range.lowerBound ..< separator),
                value: string(separator + 1 ..< range.upperBound),
                into: &rec
            )
        }
        guard !rec.fqName.isEmpty, rec.schemaVersion == nil || rec.schemaVersion == "v1" else {
            return nil
        }
        return makeRecord(kind: kind, mangledName: mangledName, rec: rec)
    }

    private func makeRecord(kind: SymbolKind, mangledName: String, rec: MutableMetadataRecord) -> MetadataRecord {
        return MetadataRecord(
            kind: kind,
            visibility: rec.visibility,
            constructorVisibilityInherited: rec.constructorVisibilityInherited,
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
            valueParameterUnsafeVarianceTypeParameterIndices: rec.valueParameterUnsafeVarianceTypeParameterIndices,
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
            isInnerClass: rec.isInnerClass,
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
            propertySetterVisibility: rec.propertySetterVisibility,
            abiReturnTypeSignature: rec.abiReturnTypeSignature,
            propertyGetterAbiReturnTypeSignature: rec.propertyGetterAbiReturnTypeSignature,
            isMutable: rec.isMutable,
            nominalTypeParametersSignature: rec.nominalTypeParametersSignature,
            nominalSupertypeSignatures: rec.nominalSupertypeSignatures,
            constValueLiteral: rec.constValueLiteral,
            nominalTypeParameters: rec.nominalTypeParameters
        )
    }

    private struct MutableMetadataRecord {
        var fqName: String = ""
        var visibility: Visibility = .public
        var constructorVisibilityInherited: Bool = false
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
        var valueParameterUnsafeVarianceTypeParameterIndices: [[Int]] = []
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
        var isInnerClass: Bool = false
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
        var propertySetterVisibility: Visibility?
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
        case "constructorVisibilityInherited":
            record.constructorVisibilityInherited = value == "1" || value == "true"
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
        case "unsafeVarianceParams":
            for entry in value.split(separator: ";") {
                let parts = entry.split(separator: ":", maxSplits: 1)
                guard parts.count == 2,
                      let parameterIndex = Int(parts[0]), parameterIndex >= 0
                else { continue }
                let typeParameterIndices = parts[1].split(separator: ",").compactMap { Int($0) }
                guard !typeParameterIndices.isEmpty else { continue }
                if record.valueParameterUnsafeVarianceTypeParameterIndices.count <= parameterIndex {
                    record.valueParameterUnsafeVarianceTypeParameterIndices += Array(
                        repeating: [],
                        count: parameterIndex + 1 - record.valueParameterUnsafeVarianceTypeParameterIndices.count
                    )
                }
                record.valueParameterUnsafeVarianceTypeParameterIndices[parameterIndex] = typeParameterIndices
            }
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
                guard parts.count == 3 || parts.count == 4,
                      let result = ContractReturnCondition(rawValue: String(parts[1])),
                      let condition = ContractArgumentCondition(rawValue: String(parts[2])) else { return nil }
                let target: ContractImplicationTarget
                if parts[0] == "receiver" {
                    target = .extensionReceiver
                } else if let index = Int(parts[0]), index >= 0 {
                    target = .valueParameter(index)
                } else {
                    return nil
                }
                let signature = parts.count == 4 ? Data(base64Encoded: String(parts[3])).flatMap { String(data: $0, encoding: .utf8) } : nil
                guard condition != .isType || signature != nil else { return nil }
                return ContractImplicationEffect(target: target, returnCondition: result,
                    argumentCondition: condition, targetTypeSignature: signature)
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
        case "innerClass":
            record.isInnerClass = value == "1" || value == "true"
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
        case "setterVisibility":
            record.propertySetterVisibility = switch value {
            case "public": .public
            case "internal": .internal
            case "protected": .protected
            default: .private
            }
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
        var retention: AnnotationRetentionKind?
        var factoryLinkName: String?
        var arguments: [String] = []
        var hasCanonicalLiterals = false
        for part in parts.dropFirst() {
            if part.hasPrefix("target:") {
                useSiteTarget = String(part.dropFirst("target:".count))
            } else if part.hasPrefix("retention:") {
                retention = AnnotationRetentionKind(rawValue: String(part.dropFirst("retention:".count)))
            } else if part.hasPrefix("factory:"),
                      let data = Data(base64Encoded: String(part.dropFirst("factory:".count))) {
                factoryLinkName = String(data: data, encoding: .utf8)
            } else if part == "literalFormat:canonical" {
                hasCanonicalLiterals = true
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
            arguments: hasCanonicalLiterals ? arguments : arguments.map(canonicalizeLegacyAnnotationArgument),
            useSiteTarget: useSiteTarget,
            retention: retention,
            factoryLinkName: factoryLinkName
        )
    }

    /// Marker-free artifacts used the historical token reconstruction. Convert
    /// their literals once at the boundary, before semantic consumers see them.
    private func canonicalizeLegacyAnnotationArgument(_ argument: String) -> String {
        var value = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        var namedPrefix = ""
        if let equal = value.firstIndex(of: "=") {
            let name = value[..<equal].trimmingCharacters(in: .whitespacesAndNewlines)
            // An '=' inside a string is content, not a named-argument prefix.
            if let first = name.first, first.isLetter || first == "_",
               name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                namedPrefix = name + "="
                value = value[value.index(after: equal)...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let dollars = String(value.prefix { $0 == "$" })
        guard value.dropFirst(dollars.count).first == "\"",
              let literal = extractKotlinStringLiteralContent(value, representation: .legacyAnnotationTokens)
        else { return argument }
        let delimiter = literal.isRaw ? "\"\"\"" : "\""
        return namedPrefix + dollars + delimiter + literal.content + delimiter
    }

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

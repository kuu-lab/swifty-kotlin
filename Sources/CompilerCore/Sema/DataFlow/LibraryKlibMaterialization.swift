import Foundation

extension DataFlowSemaPhase {
    /// Decodes the serialized Kotlin IR inside a `.klib` module and converts
    /// its declarations into `ImportedLibrarySymbolRecord`s, so the regular
    /// `.kklib` import machinery registers symbols, signatures, generics and
    /// supertype edges exactly as it does for native `.kklib` bundles.
    ///
    /// Type parameters are encoded as `T<n>` signature tokens using a
    /// module-global counter keyed by the type parameter's signature table
    /// entry, mirroring how `.kklib` emits the producer's raw symbol IDs.
    func materializeKlibRecords(
        module: KlibModule,
        interner: StringInterner,
        diagnostics: DiagnosticEngine
    ) -> [DataFlowSemaPhase.ImportedLibrarySymbolRecord] {
        let ir: KlibIrModule
        do {
            ir = try KlibIrModule(container: module.container)
        } catch {
            diagnostics.error(
                "KSWIFTK-LIB-0028",
                "Cannot decode serialized IR in \(module.path): \(error)",
                range: nil
            )
            return []
        }
        guard ir.hasIR else { return [] }

        var materializer = KlibRecordMaterializer(module: ir, interner: interner)
        for fileIndex in 0 ..< ir.fileCount {
            do {
                try materializer.materializeFile(fileIndex)
            } catch {
                diagnostics.warning(
                    "KSWIFTK-LIB-0028",
                    "Skipped file \(fileIndex) of \(module.path): \(error)",
                    range: nil
                )
            }
        }
        if materializer.skippedDeclarationCount > 0 {
            diagnostics.warning(
                "KSWIFTK-LIB-0028",
                "\(module.path): skipped \(materializer.skippedDeclarationCount) declaration(s) that cannot be imported",
                range: nil
            )
        }
        return materializer.records
    }
}

/// Signature-table identity used as the type-parameter index key: tables are
/// file-local, so the pair `(fileIndex, signatureIndex)` is required.
private struct KlibSignatureKey: Hashable {
    let fileIndex: Int
    let signatureIndex: Int
}

/// Converts decoded Kotlin IR declarations into `ImportedLibrarySymbolRecord`s.
///
/// The emitted signature strings use the `.kklib` metadata signature language
/// (`decodeImportedTypeSignature`): `Lfq.Name;` class types, `T<i>` type
/// parameters, `Q<>` nullability, `O<>`/`N<>` variance, `*` star projections
/// and `F<arity><R<recv>,params...,ret>` callable types.
private struct KlibRecordMaterializer {
    let module: KlibIrModule
    let interner: StringInterner

    private(set) var records: [DataFlowSemaPhase.ImportedLibrarySymbolRecord] = []
    private(set) var skippedDeclarationCount = 0

    /// `(fileIndex, signatureIndex)` → stable `T<n>` index.
    private var typeParameterIndexBySignature: [KlibSignatureKey: Int] = [:]
    private var nextTypeParameterIndex = 0

    /// Kotlin classifier fq names that map to primitive/special signature
    /// tokens instead of `L...;` class references.
    private static let primitiveSignatureTokens: [String: String] = [
        "kotlin.Unit": "U",
        "kotlin.Nothing": "N",
        "kotlin.Any": "A",
        "kotlin.Boolean": "Z",
        "kotlin.Byte": "B",
        "kotlin.Short": "S",
        "kotlin.Int": "I",
        "kotlin.Long": "J",
        "kotlin.Char": "C",
        "kotlin.Float": "F",
        "kotlin.Double": "D",
        "kotlin.UByte": "UB",
        "kotlin.UShort": "US",
        "kotlin.UInt": "UI",
        "kotlin.ULong": "UJ",
        "kotlin.String": "Lkotlin_String;",
    ]

    init(module: KlibIrModule, interner: StringInterner) {
        self.module = module
        self.interner = interner
    }

    // MARK: - Entry points

    mutating func materializeFile(_ fileIndex: Int) throws {
        let file = try module.file(fileIndex)
        let packageSegments = (try? module.fqName(file.fqName, fileIndex: fileIndex))
            .map { $0.isEmpty ? [] : $0.split(separator: ".").map(String.init) } ?? []
        for declarationId in file.declarationIds {
            let declaration = try module.declaration(declarationId, fileIndex: fileIndex)
            materializeDeclaration(
                declaration,
                containerFqName: packageSegments,
                ownerClass: nil,
                fileIndex: fileIndex
            )
        }
    }

    private mutating func materializeDeclaration(
        _ declaration: KlibIrDeclaration,
        containerFqName: [String],
        ownerClass: KlibClass?,
        fileIndex: Int
    ) {
        switch declaration {
        case .class(let klass):
            materializeClass(klass, containerFqName: containerFqName, fileIndex: fileIndex)
        case .constructor(let constructor):
            materializeConstructor(constructor, ownerClass: ownerClass, containerFqName: containerFqName, fileIndex: fileIndex)
        case .function(let function):
            materializeFunction(function, containerFqName: containerFqName, ownerClass: ownerClass, fileIndex: fileIndex)
        case .property(let property):
            materializeProperty(property, containerFqName: containerFqName, fileIndex: fileIndex)
        case .enumEntry(let entry):
            materializeEnumEntry(entry, containerFqName: containerFqName, fileIndex: fileIndex)
        case .field(let field):
            materializeField(field, kind: .field, containerFqName: containerFqName, fileIndex: fileIndex)
        case .typeAlias(let alias):
            materializeTypeAlias(alias, containerFqName: containerFqName, fileIndex: fileIndex)
        case .anonymousInit, .variable, .valueParameter, .typeParameter,
             .localDelegatedProperty:
            // Scope-internal declarations are not addressable by fq name; they
            // become relevant only through body translation.
            break
        }
    }

    private mutating func materializeClassMember(
        _ member: KlibIrDeclaration,
        ownerClass: KlibClass,
        ownerFqName: [String],
        fileIndex: Int
    ) {
        // Inherited members are reachable through the supertype edges that are
        // restored for the class record; enum/object synthesized members are
        // regenerated by the importer. Field flags reuse bits 6-7 for
        // static/fake-override, so the member-kind filter only applies to
        // callables and properties.
        switch member {
        case .class(let nested):
            materializeClass(nested, containerFqName: ownerFqName, fileIndex: fileIndex)
        case .constructor(let constructor):
            materializeConstructor(constructor, ownerClass: ownerClass, containerFqName: ownerFqName, fileIndex: fileIndex)
        case .function(let function):
            guard function.base.base.flags.memberKind != .fakeOverride,
                  function.base.base.flags.memberKind != .synthesized
            else { return }
            materializeFunction(function, containerFqName: ownerFqName, ownerClass: ownerClass, fileIndex: fileIndex)
        case .property(let property):
            guard property.base.flags.memberKind != .fakeOverride,
                  property.base.flags.memberKind != .synthesized
            else { return }
            materializeProperty(property, containerFqName: ownerFqName, fileIndex: fileIndex)
        case .enumEntry(let entry):
            materializeEnumEntry(entry, containerFqName: ownerFqName, fileIndex: fileIndex)
        case .field(let field):
            guard !field.base.flags.isFakeOverrideField else { return }
            materializeField(field, kind: .field, containerFqName: ownerFqName, fileIndex: fileIndex)
        default:
            break
        }
    }

    // MARK: - Nominal declarations

    private mutating func materializeClass(
        _ klass: KlibClass,
        containerFqName: [String],
        fileIndex: Int
    ) {
        guard let fqName = fqNameSegments(
            of: klass.base.symbol,
            nameIndex: klass.nameIndex,
            containerFqName: containerFqName,
            fileIndex: fileIndex
        ) else {
            skippedDeclarationCount += 1
            return
        }
        let flags = klass.base.flags
        let kind: SymbolKind = switch flags.classKind {
        case .interface: .interface
        case .enumClass: .enumClass
        case .annotationClass: .annotationClass
        case .object, .companionObject: .object
        default: .class
        }

        let supertypeFqNames = klass.superTypes.compactMap { typeIndex -> [String]? in
            guard let ref = classifierReference(of: typeIndex, fileIndex: fileIndex) else { return nil }
            return fqNameSegments(of: ref, nameIndex: nil, containerFqName: [], fileIndex: fileIndex)
        }
        var companionFqName: [String]?
        for member in klass.declarations {
            guard case .class(let nested) = member,
                  nested.base.flags.classKind == .companionObject
            else { continue }
            companionFqName = fqNameSegments(
                of: nested.base.symbol,
                nameIndex: nested.nameIndex,
                containerFqName: fqName,
                fileIndex: fileIndex
            )
            break
        }
        let sealedSubclassFqNames = klass.sealedSubclasses.compactMap { ref in
            fqNameSegments(of: ref, nameIndex: nil, containerFqName: [], fileIndex: fileIndex)
        }

        var nominalSignature: String?
        var nominalTypeParameters: String?
        if !klass.typeParameters.isEmpty {
            let args = klass.typeParameters.map {
                varianceWrapped("T\(typeParameterIndex(of: $0.base.symbol, fileIndex: fileIndex))", variance: $0.base.flags.typeParameterVariance)
            }
            nominalSignature = "L\(fqName.joined(separator: "."))<\(args.joined(separator: ","))>;"
            nominalTypeParameters = klass.typeParameters.map {
                "T\(typeParameterIndex(of: $0.base.symbol, fileIndex: fileIndex)):\(varianceLetter($0.base.flags.typeParameterVariance))"
            }.joined(separator: ",")
        }

        append(
            DataFlowSemaPhase.ImportedLibrarySymbolRecord(
                kind: kind,
                mangledName: mangledName(of: klass.base.symbol, fileIndex: fileIndex),
                fqName: fqName.map { interner.intern($0) },
                superFQName: supertypeFqNames.first.map { $0.map { interner.intern($0) } },
                superFQNames: supertypeFqNames.map { $0.map { interner.intern($0) } },
                companionObjectFQName: companionFqName.map { $0.map { interner.intern($0) } },
                isDataClass: flags.isData,
                isOpenClass: flags.modality == .open,
                modality: metadataModality(flags.modality),
                isSealedClass: flags.modality == .sealed,
                isFunInterface: flags.isFunInterface,
                isValueClass: flags.isValueClass,
                isExpect: flags.isExpectClass,
                valueClassUnderlyingTypeSig: klass.inlineClassRepresentation
                    .flatMap { encodeType($0.underlyingPropertyType, fileIndex: fileIndex) },
                annotations: annotationRecords(klass.base.annotations, fileIndex: fileIndex),
                sealedSubclassFQNames: sealedSubclassFqNames.map { $0.map { interner.intern($0) } },
                nominalTypeParametersSignature: nominalSignature,
                nominalSupertypeSignatures: klass.superTypes.compactMap {
                    encodeType($0, fileIndex: fileIndex)
                },
                nominalTypeParameters: nominalTypeParameters
            )
        )

        for member in klass.declarations {
            materializeClassMember(member, ownerClass: klass, ownerFqName: fqName, fileIndex: fileIndex)
        }
    }

    // MARK: - Callables

    private mutating func materializeFunction(
        _ function: KlibFunction,
        containerFqName: [String],
        ownerClass: KlibClass?,
        fileIndex: Int
    ) {
        let base = function.base
        guard let fqName = fqNameSegments(
            of: base.base.symbol,
            nameIndex: base.nameType.nameIndex,
            containerFqName: containerFqName,
            fileIndex: fileIndex
        ) else {
            skippedDeclarationCount += 1
            return
        }
        materializeCallable(
            base,
            kind: .function,
            fqName: fqName,
            ownerClass: ownerClass,
            overridden: function.overridden,
            fileIndex: fileIndex
        )
    }

    private mutating func materializeConstructor(
        _ constructor: KlibConstructor,
        ownerClass: KlibClass?,
        containerFqName: [String],
        fileIndex: Int
    ) {
        let base = constructor.base
        guard let ownerClass else {
            skippedDeclarationCount += 1
            return
        }
        guard let fqName = fqNameSegments(
            of: base.base.symbol,
            nameIndex: nil,
            containerFqName: containerFqName + ["<init>"],
            fileIndex: fileIndex
        ) else {
            skippedDeclarationCount += 1
            return
        }
        materializeCallable(
            base,
            kind: .constructor,
            fqName: fqName,
            ownerClass: ownerClass,
            overridden: [],
            fileIndex: fileIndex
        )
    }

    private mutating func materializeCallable(
        _ base: KlibFunctionBase,
        kind: SymbolKind,
        fqName: [String],
        ownerClass: KlibClass?,
        overridden: [KlibSymbolRef],
        fileIndex: Int
    ) {
        let ownerSelfType = ownerClass.flatMap {
            nominalUseSiteSignature($0, fqName: Array(fqName.dropLast()), fileIndex: fileIndex)
        }
        let receiverSignature: String?
        if let extensionReceiver = base.extensionReceiver {
            receiverSignature = encodeType(extensionReceiver.nameType.typeIndex, fileIndex: fileIndex)
        } else if base.dispatchReceiver != nil || kind == .constructor {
            receiverSignature = ownerSelfType
        } else {
            receiverSignature = nil
        }
        let returnType = kind == .constructor
            ? ownerSelfType
            : encodeType(base.nameType.typeIndex, fileIndex: fileIndex)
        guard let returnType else {
            skippedDeclarationCount += 1
            return
        }

        var signature = base.base.flags.isSuspend ? "SF" : "F"
        signature += "\(base.regularParameters.count)<"
        if !base.contextParameters.isEmpty {
            let contextTypes = base.contextParameters.compactMap {
                encodeType($0.nameType.typeIndex, fileIndex: fileIndex)
            }
            guard contextTypes.count == base.contextParameters.count else {
                skippedDeclarationCount += 1
                return
            }
            signature += "C\(contextTypes.count)<\(contextTypes.joined(separator: ","))>,"
        }
        if let receiverSignature {
            signature += "R\(receiverSignature),"
        }
        for parameter in base.regularParameters {
            guard let encoded = encodeType(parameter.nameType.typeIndex, fileIndex: fileIndex) else {
                skippedDeclarationCount += 1
                return
            }
            signature += "\(encoded),"
        }
        signature += "\(returnType)>"

        let ownerTypeParameters = ownerClass?.typeParameters ?? []
        let callableTypeParameterSignatures = (ownerTypeParameters + base.typeParameters).map {
            "T\(typeParameterIndex(of: $0.base.symbol, fileIndex: fileIndex))"
        }
        let upperBounds = (ownerTypeParameters + base.typeParameters).map {
            $0.superTypes.compactMap { encodeType($0, fileIndex: fileIndex) }
        }
        var reifiedIndices: Set<Int> = []
        for (index, parameter) in base.typeParameters.enumerated() where parameter.base.flags.isReified {
            reifiedIndices.insert(ownerTypeParameters.count + index)
        }

        append(
            DataFlowSemaPhase.ImportedLibrarySymbolRecord(
                kind: kind,
                mangledName: mangledName(of: base.base.symbol, fileIndex: fileIndex),
                fqName: fqName.map { interner.intern($0) },
                arity: base.regularParameters.count,
                isSuspend: base.base.flags.isSuspend,
                isInline: base.base.flags.isInline || base.base.flags.isInlineAccessor,
                isOperator: base.base.flags.isOperator,
                isOverride: !overridden.isEmpty,
                valueParameterIsVararg: base.regularParameters.map { $0.varargElementType != nil },
                valueParameterHasDefaultValues: base.regularParameters.map { $0.defaultValueIndex != nil },
                valueParameterNames: base.regularParameters.map {
                    (try? module.string($0.nameType.nameIndex, fileIndex: fileIndex)) ?? ""
                },
                reifiedTypeParameterIndices: reifiedIndices,
                typeSignature: signature,
                typeParameterUpperBoundsSignatures: upperBounds,
                callableTypeParameterSignatures: callableTypeParameterSignatures,
                isExpect: base.base.flags.isExpectFunction,
                annotations: annotationRecords(base.base.annotations, fileIndex: fileIndex)
            )
        )
    }

    // MARK: - Properties and fields

    private mutating func materializeProperty(
        _ property: KlibProperty,
        containerFqName: [String],
        fileIndex: Int
    ) {
        guard let fqName = fqNameSegments(
            of: property.base.symbol,
            nameIndex: property.nameIndex,
            containerFqName: containerFqName,
            fileIndex: fileIndex
        ) else {
            skippedDeclarationCount += 1
            return
        }
        let name = (try? module.string(property.nameIndex, fileIndex: fileIndex)) ?? "_"
        // The property type lives on its backing field or getter return type.
        let propertyTypeIndex = property.backingField?.nameType.typeIndex
            ?? property.getter?.base.nameType.typeIndex
        guard let propertyTypeIndex,
              let propertySignature = encodeType(propertyTypeIndex, fileIndex: fileIndex)
        else {
            skippedDeclarationCount += 1
            return
        }

        append(
            DataFlowSemaPhase.ImportedLibrarySymbolRecord(
                kind: .property,
                mangledName: mangledName(of: property.base.symbol, fileIndex: fileIndex),
                fqName: fqName.map { interner.intern($0) },
                typeSignature: propertySignature,
                isExpect: property.base.flags.isExpectProperty,
                annotations: annotationRecords(property.base.annotations, fileIndex: fileIndex),
                propertyReceiverTypeSignature: property.getter?.base.extensionReceiver
                    .flatMap { encodeType($0.nameType.typeIndex, fileIndex: fileIndex) },
                isMutable: property.base.flags.isVar,
                constValueLiteral: constLiteral(property.backingField?.initializerIndex, fileIndex: fileIndex)
            )
        )

        if let field = property.backingField {
            materializeField(
                field,
                kind: .backingField,
                nameOverride: "$backing_\(name)",
                containerFqName: containerFqName,
                fileIndex: fileIndex
            )
        }
    }

    private mutating func materializeField(
        _ field: KlibField,
        kind: SymbolKind,
        nameOverride: String? = nil,
        containerFqName: [String],
        fileIndex: Int
    ) {
        guard let fqName = fqNameSegments(
            of: field.base.symbol,
            nameIndex: field.nameType.nameIndex,
            nameOverride: nameOverride,
            containerFqName: containerFqName,
            fileIndex: fileIndex
        ) else {
            skippedDeclarationCount += 1
            return
        }
        guard let signature = encodeType(field.nameType.typeIndex, fileIndex: fileIndex) else {
            skippedDeclarationCount += 1
            return
        }
        append(
            DataFlowSemaPhase.ImportedLibrarySymbolRecord(
                kind: kind,
                mangledName: mangledName(of: field.base.symbol, fileIndex: fileIndex),
                fqName: fqName.map { interner.intern($0) },
                typeSignature: signature,
                annotations: annotationRecords(field.base.annotations, fileIndex: fileIndex),
                isMutable: !field.base.flags.isFinalField,
                constValueLiteral: constLiteral(field.initializerIndex, fileIndex: fileIndex)
            )
        )
    }

    private mutating func materializeEnumEntry(
        _ entry: KlibEnumEntry,
        containerFqName: [String],
        fileIndex: Int
    ) {
        guard let fqName = fqNameSegments(
            of: entry.base.symbol,
            nameIndex: entry.nameIndex,
            containerFqName: containerFqName,
            fileIndex: fileIndex
        ) else {
            skippedDeclarationCount += 1
            return
        }
        append(
            DataFlowSemaPhase.ImportedLibrarySymbolRecord(
                kind: .field,
                mangledName: mangledName(of: entry.base.symbol, fileIndex: fileIndex),
                fqName: fqName.map { interner.intern($0) },
                typeSignature: "L\(containerFqName.joined(separator: "."));",
                annotations: annotationRecords(entry.base.annotations, fileIndex: fileIndex)
            )
        )
    }

    private mutating func materializeTypeAlias(
        _ alias: KlibTypeAlias,
        containerFqName: [String],
        fileIndex: Int
    ) {
        guard let fqName = fqNameSegments(
            of: alias.base.symbol,
            nameIndex: alias.nameType.nameIndex,
            containerFqName: containerFqName,
            fileIndex: fileIndex
        ) else {
            skippedDeclarationCount += 1
            return
        }
        guard let signature = encodeType(alias.nameType.typeIndex, fileIndex: fileIndex) else {
            skippedDeclarationCount += 1
            return
        }
        append(
            DataFlowSemaPhase.ImportedLibrarySymbolRecord(
                kind: .typeAlias,
                mangledName: mangledName(of: alias.base.symbol, fileIndex: fileIndex),
                fqName: fqName.map { interner.intern($0) },
                typeSignature: signature,
                isActual: alias.base.flags.isActual,
                annotations: annotationRecords(alias.base.annotations, fileIndex: fileIndex)
            )
        )
    }

    // MARK: - Fq-name and signature resolution

    /// Resolves the declaration's fq-name segments from its signature.
    /// `CommonIdSignature` carries package + declaration segments directly;
    /// file-local/private declarations fall back to the walk context's
    /// container fq-name plus the declaration's own name.
    private func fqNameSegments(
        of symbol: KlibSymbolRef,
        nameIndex: Int32?,
        nameOverride: String? = nil,
        containerFqName: [String],
        fileIndex: Int
    ) -> [String]? {
        if case .common(let packageFqName, let declarationFqName, _, _, _) =
            try? module.signature(symbol.signatureIndex, fileIndex: fileIndex)
        {
            let package = packageFqName.compactMap { try? module.string($0, fileIndex: fileIndex) }
            let declaration = declarationFqName.compactMap { try? module.string($0, fileIndex: fileIndex) }
            guard package.count == packageFqName.count,
                  declaration.count == declarationFqName.count,
                  !declaration.isEmpty
            else { return nil }
            return package + declaration
        }
        guard let name = nameOverride ?? nameIndex.flatMap({
            try? module.string($0, fileIndex: fileIndex)
        }), !name.isEmpty
        else {
            return nil
        }
        return containerFqName + [name]
    }

    /// `T<n>` index for a type parameter's signature entry, stable across the
    /// whole module so owner and member records agree on the same indices.
    private mutating func typeParameterIndex(of symbol: KlibSymbolRef, fileIndex: Int) -> Int {
        let key = KlibSignatureKey(fileIndex: fileIndex, signatureIndex: symbol.signatureIndex)
        if let index = typeParameterIndexBySignature[key] { return index }
        let index = nextTypeParameterIndex
        nextTypeParameterIndex += 1
        typeParameterIndexBySignature[key] = index
        return index
    }

    /// `Lfq.Name<T0,...>;` — the use-site self type of a nominal declaration
    /// (invariant type arguments), used for member receivers and constructor
    /// return types.
    private mutating func nominalUseSiteSignature(
        _ klass: KlibClass,
        fqName: [String],
        fileIndex: Int
    ) -> String {
        var text = "L\(fqName.joined(separator: "."))"
        if !klass.typeParameters.isEmpty {
            let args = klass.typeParameters.map {
                "T\(typeParameterIndex(of: $0.base.symbol, fileIndex: fileIndex))"
            }
            text += "<\(args.joined(separator: ","))>"
        }
        return text + ";"
    }

    private func classifierReference(of typeIndex: Int32, fileIndex: Int) -> KlibSymbolRef? {
        guard let type = try? module.type(typeIndex, fileIndex: fileIndex) else { return nil }
        switch type {
        case .simple(let classifier, _, _, _), .legacySimple(let classifier, _, _, _):
            return classifier
        default:
            return nil
        }
    }

    // MARK: - Type signature encoding

    /// Encodes a `types`-table entry into the `.kklib` signature language.
    private mutating func encodeType(_ typeIndex: Int32, fileIndex: Int) -> String? {
        guard let type = try? module.type(typeIndex, fileIndex: fileIndex) else { return nil }
        switch type {
        case .simple(let classifier, let nullability, let arguments, _):
            guard var encoded = encodeClassifier(classifier, arguments: arguments, fileIndex: fileIndex)
            else { return nil }
            if nullability == .markedNullable { encoded = "Q<\(encoded)>" }
            return encoded
        case .legacySimple(let classifier, let hasQuestionMark, let arguments, _):
            guard var encoded = encodeClassifier(classifier, arguments: arguments, fileIndex: fileIndex)
            else { return nil }
            if hasQuestionMark { encoded = "Q<\(encoded)>" }
            return encoded
        case .dynamic, .error:
            return "E"
        case .definitelyNotNull(let types):
            let parts = types.compactMap { encodeType($0, fileIndex: fileIndex) }
            guard !parts.isEmpty else { return nil }
            return "X<\(parts.joined(separator: "&"))>"
        }
    }

    private mutating func encodeClassifier(
        _ classifier: KlibSymbolRef,
        arguments: [KlibTypeArgument],
        fileIndex: Int
    ) -> String? {
        if classifier.kind == .typeParameter {
            return "T\(typeParameterIndex(of: classifier, fileIndex: fileIndex))"
        }
        guard let segments = fqNameSegments(
            of: classifier,
            nameIndex: nil,
            containerFqName: [],
            fileIndex: fileIndex
        ) else {
            return "E"
        }
        let dotted = segments.joined(separator: ".")
        if arguments.isEmpty, let token = Self.primitiveSignatureTokens[dotted] {
            return token
        }
        if dotted == "kotlin.reflect.KClass" || dotted == "kotlin.KClass",
           arguments.count == 1, case .type(let index, _) = arguments[0],
           let inner = encodeType(index, fileIndex: fileIndex)
        {
            return "KC<\(inner)>"
        }
        var text = "L\(dotted)"
        if !arguments.isEmpty {
            let encodedArguments = arguments.map { argument -> String in
                switch argument {
                case .star:
                    return "*"
                case .type(let index, let variance):
                    guard let inner = encodeType(index, fileIndex: fileIndex) else { return "*" }
                    return varianceWrapped(inner, variance: variance)
                }
            }
            text += "<\(encodedArguments.joined(separator: ","))>"
        }
        return text + ";"
    }

    private func varianceWrapped(_ type: String, variance: KlibVariance) -> String {
        switch variance {
        case .out: "O<\(type)>"
        case .in: "N<\(type)>"
        case .invariant: type
        }
    }

    private func varianceLetter(_ variance: KlibVariance) -> String {
        switch variance {
        case .invariant: "i"
        case .out: "o"
        case .in: "n"
        }
    }

    private func metadataModality(_ modality: KlibModality) -> MetadataModality {
        switch modality {
        case .open: .open
        // Sealed classes are abstract; `isSealedClass` carries the rest.
        case .abstract, .sealed: .abstract
        case .final: .final
        }
    }

    // MARK: - Annotations and constants

    private func annotationRecords(_ annotations: [KlibAnnotation], fileIndex: Int) -> [MetadataAnnotationRecord] {
        annotations.compactMap { annotation in
            guard let constructorFqName = fqNameSegments(
                of: annotation.symbol,
                nameIndex: nil,
                containerFqName: [],
                fileIndex: fileIndex
            ), constructorFqName.count >= 2
            else { return nil }
            return MetadataAnnotationRecord(
                annotationFQName: constructorFqName.dropLast().joined(separator: "."),
                arguments: annotation.arguments.compactMap { renderLiteral($0, fileIndex: fileIndex) }
            )
        }
    }

    /// `const val` initializers are `bodies` entries wrapping a const
    /// expression; render them into `MetadataConstValueCoder`'s `<tag>:<payload>`.
    private func constLiteral(_ bodyIndex: Int32?, fileIndex: Int) -> String? {
        guard let bodyIndex,
              let statement = try? module.body(bodyIndex, fileIndex: fileIndex),
              case .expression(let expression) = statement.kind
        else { return nil }
        switch expression.kind {
        case .constInt(let value): return "i:\(value)"
        case .constLong(let value): return "l:\(value)"
        case .constBool(let value): return "b:\(value ? 1 : 0)"
        case .constChar(let value): return "c:\(value)"
        case .constFloat(let bits): return "f:\(bits)"
        case .constDouble(let bits): return "d:\(bits)"
        case .constString(let index):
            guard let text = try? module.string(index, fileIndex: fileIndex) else { return nil }
            return "s:\(Data(text.utf8).base64EncodedString())"
        default:
            return nil
        }
    }

    private func renderLiteral(_ expression: KlibIrExpression, fileIndex: Int) -> String? {
        switch expression.kind {
        case .constString(let index):
            return try? module.string(index, fileIndex: fileIndex)
        case .constInt(let value): return "\(value)"
        case .constLong(let value): return "\(value)L"
        case .constBool(let value): return value ? "true" : "false"
        case .constChar(let value): return "'\(value)'"
        case .constFloat(let bits): return "\(Float(bitPattern: bits))f"
        case .constDouble(let bits): return "\(Double(bitPattern: bits))"
        default: return nil
        }
    }

    private func mangledName(of symbol: KlibSymbolRef, fileIndex: Int) -> String {
        "klib\(fileIndex)_\(symbol.signatureIndex)"
    }

    private mutating func append(_ record: DataFlowSemaPhase.ImportedLibrarySymbolRecord) {
        records.append(record)
    }
}

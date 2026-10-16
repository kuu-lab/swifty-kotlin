extension DataFlowSemaPhase {
    /// Register a v3 shell without constructing a full MetadataRecord or
    /// parsing any signature/layout/annotation from the declaration body.
    func makeImportedLibraryIndexRecord(
        _ record: CompactMetadataIndexRecord,
        path: String,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        nominalTypeParametersByFQName: [String: String]
    ) -> ImportedLibrarySymbolRecord? {
        if record.kind == .function || record.kind == .constructor {
            guard (0 ... ImportedLibraryLimits.maxCallableArity).contains(record.arity) else {
                diagnostics.error(
                    "KSWIFTK-LIB-0024",
                    "Callable arity \(record.arity) in '\(path)' is outside the supported range 0...\(ImportedLibraryLimits.maxCallableArity)",
                    range: nil
                )
                return nil
            }
        }
        func fqName(_ value: String) -> [InternedString] {
            interner.internQualifiedName(value)
        }
        func optionalFQName(_ value: String?) -> [InternedString]? {
            guard let value else { return nil }
            let result = fqName(value)
            return result.isEmpty ? nil : result
        }
        let name = fqName(record.fqName)
        guard !name.isEmpty else { return nil }
        let ownerSignature = record.fqName.lastIndex(of: ".").flatMap {
            nominalTypeParametersByFQName[String(record.fqName[..<$0])]
        }
        return ImportedLibrarySymbolRecord(
            kind: record.kind,
            visibility: record.visibility,
            constructorVisibilityInherited: record.constructorVisibilityInherited,
            mangledName: record.mangledName,
            fqName: name,
            arity: record.arity,
            isSuspend: record.isSuspend,
            isInline: record.isInline,
            isOperator: record.isOperator,
            isInfix: record.isInfix,
            isOverride: record.isOverride,
            isMemberExtension: record.isMemberExtension,
            receiverOwnerFQName: optionalFQName(record.receiverOwnerFQName),
            defaultStubExternalLinkName: record.defaultStubExternalLinkName,
            externalLinkName: record.externalLinkName,
            companionObjectFQName: optionalFQName(record.companionObjectFQName),
            objectInitializerLinkName: record.objectInitializerLinkName,
            companionInitializerLinkName: record.companionInitializerLinkName,
            enumStaticInitLinkName: record.enumStaticInitLinkName,
            isDataClass: record.isDataClass,
            isOpenClass: record.isOpenClass,
            isInnerClass: record.isInnerClass,
            modality: record.modality,
            isSealedClass: record.isSealedClass,
            isFunInterface: record.isFunInterface,
            isValueClass: record.isValueClass,
            isExpect: record.isExpect,
            isActual: record.isActual,
            propertyReceiverTypeSignature: record.propertyReceiverTypeSignature,
            propertyGetterExternalLinkName: record.propertyGetterExternalLinkName,
            propertySetterVisibility: record.propertySetterVisibility,
            isMutable: record.isMutable,
            nominalTypeParametersSignature: record.nominalTypeParametersSignature,
            ownerNominalTypeParametersSignature: ownerSignature
        )
    }
}

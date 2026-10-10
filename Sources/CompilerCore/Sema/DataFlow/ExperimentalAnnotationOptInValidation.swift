import Foundation

extension DataFlowSemaPhase {
    func validateExperimentalAnnotationOptIn(
        for annotation: AnnotationNode,
        in file: ASTFile,
        scopeSymbol: SymbolID?,
        range: SourceRange?,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        globalOptInMarkerNames: [String]
    ) {
        guard let annotationSymbol = resolveAnnotationSymbol(
            named: annotation.name,
            in: file,
            symbols: symbols,
            interner: interner
        ) else {
            return
        }

        let annotationMetadata = symbols.annotations(for: annotationSymbol)
        guard !annotationMetadata.contains(where: {
            KnownCompilerAnnotation.requiresOptIn.matches($0.annotationFQName)
        }) else {
            // Applying the marker itself declares an experimental API; it does not require opt-in.
            return
        }

        var requiredMarkers: [SymbolID] = []
        for metadata in annotationMetadata {
            guard let marker = resolveAnnotationSymbol(
                named: metadata.annotationFQName,
                in: file,
                symbols: symbols,
                interner: interner
            ), symbols.annotations(for: marker).contains(where: {
                KnownCompilerAnnotation.requiresOptIn.matches($0.annotationFQName)
            }), !requiredMarkers.contains(marker) else {
                continue
            }
            requiredMarkers.append(marker)
        }
        guard !requiredMarkers.isEmpty else {
            return
        }
        bindings.recordValidatedAnnotationOptIn(usageID: annotation.usageID, markers: Set(requiredMarkers))

        var optedInMarkers = Set<SymbolID>()
        for markerName in globalOptInMarkerNames {
            if let marker = resolveAnnotationSymbol(
                named: markerName,
                in: file,
                symbols: symbols,
                interner: interner
            ) {
                optedInMarkers.insert(marker)
            }
        }

        collectExplicitOptInMarkers(
            from: file.annotations.map {
                MetadataAnnotationRecord(
                    annotationFQName: $0.name,
                    arguments: $0.arguments,
                    useSiteTarget: $0.useSiteTarget
                )
            },
            in: file,
            symbols: symbols,
            interner: interner,
            into: &optedInMarkers
        )

        var currentScope = scopeSymbol
        var isCurrentScope = true
        while let symbol = currentScope {
            let scopeAnnotations = symbols.annotations(for: symbol)
            collectExplicitOptInMarkers(
                from: scopeAnnotations,
                in: file,
                symbols: symbols,
                interner: interner,
                into: &optedInMarkers
            )
            if !isCurrentScope {
                collectMarkerScopeAnnotations(
                    from: scopeAnnotations,
                    in: file,
                    symbols: symbols,
                    interner: interner,
                    into: &optedInMarkers
                )
            }
            currentScope = symbols.parentSymbol(for: symbol)
            isCurrentScope = false
        }

        for marker in requiredMarkers where !optedInMarkers.contains(marker) {
            guard let markerSymbol = symbols.symbol(marker) else {
                continue
            }
            let markerName = markerSymbol.fqName.map(interner.resolve).joined(separator: ".")
            let requiresOptIn = symbols.annotations(for: marker).first {
                KnownCompilerAnnotation.requiresOptIn.matches($0.annotationFQName)
            }
            let isWarning = requiresOptIn?.arguments.contains(where: {
                $0.localizedCaseInsensitiveContains("WARNING")
            }) ?? false
            let message = "'\(markerName)' requires opt-in. Annotate the usage with '@\(markerName)' or '@OptIn(\(markerName)::class).'"
            if isWarning {
                diagnostics.warning("KSWIFTK-SEMA-OPT-IN", message, range: range)
            } else {
                diagnostics.error("KSWIFTK-SEMA-OPT-IN", message, range: range)
            }
        }
    }

    private func collectExplicitOptInMarkers(
        from annotations: [MetadataAnnotationRecord],
        in file: ASTFile,
        symbols: SymbolTable,
        interner: StringInterner,
        into markers: inout Set<SymbolID>
    ) {
        for annotation in annotations where KnownCompilerAnnotation.optIn.matches(annotation.annotationFQName) {
            for rawName in optInMarkerNames(in: annotation.arguments) {
                if let marker = resolveAnnotationSymbol(
                    named: rawName,
                    in: file,
                    symbols: symbols,
                    interner: interner
                ) {
                    markers.insert(marker)
                }
            }
        }
    }

    private func collectMarkerScopeAnnotations(
        from annotations: [MetadataAnnotationRecord],
        in file: ASTFile,
        symbols: SymbolTable,
        interner: StringInterner,
        into markers: inout Set<SymbolID>
    ) {
        for annotation in annotations {
            guard let annotationSymbol = resolveAnnotationSymbol(
                named: annotation.annotationFQName,
                in: file,
                symbols: symbols,
                interner: interner
            ) else {
                continue
            }
            if symbols.annotations(for: annotationSymbol).contains(where: {
                KnownCompilerAnnotation.requiresOptIn.matches($0.annotationFQName)
            }) {
                markers.insert(annotationSymbol)
            }
            for metaAnnotation in symbols.annotations(for: annotationSymbol) {
                guard let marker = resolveAnnotationSymbol(
                    named: metaAnnotation.annotationFQName,
                    in: file,
                    symbols: symbols,
                    interner: interner
                ), symbols.annotations(for: marker).contains(where: {
                    KnownCompilerAnnotation.requiresOptIn.matches($0.annotationFQName)
                }) else {
                    continue
                }
                markers.insert(marker)
            }
        }
    }

    private func optInMarkerNames(in arguments: [String]) -> [String] {
        arguments.compactMap { rawArgument in
            var value = rawArgument.trimmingCharacters(in: .whitespacesAndNewlines)
            if let equal = value.firstIndex(of: "=") {
                value = String(value[value.index(after: equal)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            value = value
                .replacingOccurrences(of: ":: class", with: "")
                .replacingOccurrences(of: "::class", with: "")
                .replacingOccurrences(of: ".class", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\\\"'()[] "))
            return value.isEmpty ? nil : value
        }
    }
}

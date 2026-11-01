import Foundation

/// Call-site-independent memoization for opt-in checks. A symbol's
/// annotations and its owning file are fixed after header collection, and the
/// only symbols `resolveAnnotationClassSymbol` can return — `.annotationClass`
/// kinds — are all declared at header time (local symbols defined during type
/// checking are never annotation classes), so the results cannot go stale
/// mid-run.
final class OptInResolutionCache {
    struct RequirementsKey: Hashable {
        let symbolID: SymbolID
        /// The file `resolveAnnotationClassSymbol` resolves against: the
        /// symbol's own file when recorded, else the file being checked.
        let fileID: FileID?
    }

    struct AnnotationClassKey: Hashable {
        let rawName: String
        let fileID: FileID?
    }

    fileprivate var requirementsBySymbol: [RequirementsKey: [TypeCheckHelpers.OptInRequirement]] = [:]
    fileprivate var annotationClassSymbols: [AnnotationClassKey: SymbolID?] = [:]
}

extension TypeCheckHelpers {
    fileprivate enum OptInLevel {
        case warning
        case error
    }

    fileprivate struct OptInRequirement {
        let markerSymbol: SymbolID
        let markerName: String
        let message: String
        let level: OptInLevel
    }

    func checkOptIn(
        for symbolID: SymbolID,
        constructorTypeAlias: SymbolID? = nil,
        ctx: TypeInferenceContext,
        range: SourceRange?,
        diagnostics: DiagnosticEngine
    ) {
        var requirements = requiredOptInRequirements(for: symbolID, ctx: ctx)
        var isAnnotationConstruction = false
        if ctx.sema.symbols.symbol(symbolID)?.kind == .constructor,
           let owner = ctx.sema.symbols.parentSymbol(for: symbolID) {
            var markers = Set(requirements.map(\.markerSymbol))
            // An alias constructor inherits the alias's markers, not those of
            // its expanded class. The constructor's own markers still apply.
            for requirement in requiredOptInRequirements(for: constructorTypeAlias ?? owner, ctx: ctx)
                where markers.insert(requirement.markerSymbol).inserted {
                requirements.append(requirement)
            }
            if let validated = ctx.annotationOptInValidation,
               validated.owner == owner, validated.range == range {
                requirements.removeAll { validated.markers.contains($0.markerSymbol) }
                isAnnotationConstruction = true
            }
        }
        if let symbolKind = ctx.sema.symbols.symbol(symbolID)?.kind,
           (symbolKind == .function || symbolKind == .property),
           let owner = ctx.sema.symbols.parentSymbol(for: symbolID),
           let ownerKind = ctx.sema.symbols.symbol(owner)?.kind,
           (ownerKind == .class || ownerKind == .interface || ownerKind == .object || ownerKind == .enumClass)
        {
            var markers = Set(requirements.map(\.markerSymbol))
            for requirement in requiredOptInRequirements(for: owner, ctx: ctx)
                where markers.insert(requirement.markerSymbol).inserted {
                requirements.append(requirement)
            }
        }
        // Signature types remain dynamic: expression bodies can refine a header's
        // placeholder after the annotation cache has already been populated.
        // An annotation application's synthetic factory call checks the annotation
        // class, not a callable signature. Nested explicit calls keep their checks.
        var signatureTypes: [TypeID] = []
        if let propertyType = ctx.sema.symbols.propertyType(for: symbolID) {
            signatureTypes.append(propertyType)
            if let receiverType = ctx.sema.symbols.extensionPropertyReceiverType(for: symbolID) {
                signatureTypes.append(receiverType)
            }
        } else if !isAnnotationConstruction,
                  let signature = ctx.sema.symbols.functionSignature(for: symbolID),
                  ctx.sema.symbols.accessorOwnerProperty(for: symbolID) == nil,
                  ctx.sema.symbols.parentSymbol(for: symbolID)
                    .flatMap({ ctx.sema.symbols.symbol($0)?.kind }) != .property {
            if ctx.sema.symbols.symbol(symbolID)?.kind != .constructor {
                signatureTypes.append(signature.returnType)
                if let receiverType = signature.receiverType {
                    signatureTypes.append(receiverType)
                }
            }
            signatureTypes.append(contentsOf: signature.parameterTypes)
        }
        requirements.append(contentsOf: requiredOptInRequirements(forTypes: signatureTypes, ctx: ctx))
        emitOptInRequirements(requirements, ctx: ctx, range: range, diagnostics: diagnostics)
    }

    private func emitOptInRequirements(
        _ requirements: [OptInRequirement],
        ctx: TypeInferenceContext,
        range: SourceRange?,
        diagnostics: DiagnosticEngine
    ) {
        guard !requirements.isEmpty else { return }
        var reportedMarkers: Set<SymbolID> = []
        let optedInMarkers = activeOptInMarkers(in: ctx)
        for requirement in requirements {
            guard !optedInMarkers.contains(requirement.markerSymbol),
                  reportedMarkers.insert(requirement.markerSymbol).inserted else {
                continue
            }

            let messageSuffix = requirement.message.isEmpty ? "" : " \(requirement.message)"
            let diagnosticMessage = "'\(requirement.markerName)' requires opt-in. " +
                "Annotate the usage with '@\(requirement.markerName)' or '@OptIn(\(requirement.markerName)::class)'.\(messageSuffix)"

            switch requirement.level {
            case .warning:
                diagnostics.warning(
                    "KSWIFTK-SEMA-OPT-IN",
                    diagnosticMessage,
                    range: range
                )
            case .error:
                diagnostics.error(
                    "KSWIFTK-SEMA-OPT-IN",
                    diagnosticMessage,
                    range: range
                )
            }
        }
    }

    func checkOptInForType(
        _ type: TypeID,
        ctx: TypeInferenceContext,
        range: SourceRange?,
        diagnostics: DiagnosticEngine
    ) {
        emitOptInRequirements(
            requiredOptInRequirements(forTypes: [type], ctx: ctx),
            ctx: ctx, range: range, diagnostics: diagnostics
        )
    }

    func checkSubclassOptInRequirements(
        forClassLike symbol: SymbolID,
        ctx: TypeInferenceContext,
        range: SourceRange?,
        diagnostics: DiagnosticEngine
    ) {
        // Only direct supertypes impose the requirement. A subclass that
        // consents via '@OptIn'/the marker consumes it and does not re-impose
        // it on its own subclasses; '@SubclassOptInRequired' is the only form
        // that propagates the requirement further, matching kotlinc.
        var optedInMarkers = activeOptInMarkers(in: ctx)
        // '@SubclassOptInRequired(M::class)' on the checked class or an
        // enclosing declaration consents to subclassing M-gated supertypes
        // within its scope — including nested classes — without consenting to
        // ordinary usages of M-marked API the way '@OptIn' does.
        var consentingDecl: SymbolID? = symbol
        while let current = consentingDecl {
            let file = sourceFile(for: current, ctx: ctx) ?? currentFile(in: ctx)
            for annotation in ctx.sema.symbols.annotations(for: current)
                where KnownCompilerAnnotation.subclassOptInRequired.matches(annotation.annotationFQName)
            {
                for markerName in parseOptInMarkerNames(annotation.arguments) {
                    if let markerSymbol = resolveAnnotationClassSymbol(
                        named: markerName,
                        file: file,
                        ctx: ctx
                    ) {
                        optedInMarkers.insert(markerSymbol)
                    }
                }
            }
            consentingDecl = ctx.sema.symbols.parentSymbol(for: current)
        }

        for supertype in ctx.sema.symbols.directSupertypes(for: symbol) {
            for annotation in ctx.sema.symbols.annotations(for: supertype)
                where KnownCompilerAnnotation.subclassOptInRequired.matches(annotation.annotationFQName)
            {
                validateSubclassOptInRequirement(
                    annotation,
                    inheritedFrom: supertype,
                    optedInMarkers: optedInMarkers,
                    ctx: ctx,
                    range: range,
                    diagnostics: diagnostics
                )
            }
        }
    }

    private func requiredOptInRequirements(
        forTypes types: [TypeID],
        ctx: TypeInferenceContext
    ) -> [OptInRequirement] {
        var requirements: [OptInRequirement] = []
        var visitedTypes: Set<TypeID> = []
        var visitedSymbols: Set<SymbolID> = []
        func visit(_ type: TypeID) {
            guard visitedTypes.insert(type).inserted else { return }
            switch ctx.sema.types.kind(of: type) {
            case .unit, .nullableUnit, .platformUnit, .any, .stringStruct, .primitive, .typeParam, .nothing, .error:
                break
            case let .classType(classType):
                if visitedSymbols.insert(classType.classSymbol).inserted {
                    requirements.append(contentsOf: requiredOptInRequirements(for: classType.classSymbol, ctx: ctx))
                }
                for argument in classType.args {
                    if let type = typeArgType(argument) { visit(type) }
                }
            case let .functionType(functionType):
                if let receiver = functionType.receiver { visit(receiver) }
                for parameter in functionType.params { visit(parameter) }
                visit(functionType.returnType)
            case let .intersection(parts):
                for part in parts { visit(part) }
            case let .kClassType(kClassType):
                visit(kClassType.argument)
            }
        }
        for type in types { visit(type) }
        return requirements
    }

    private func requiredOptInRequirements(
        for symbolID: SymbolID,
        ctx: TypeInferenceContext
    ) -> [OptInRequirement] {
        let annotations = ctx.sema.symbols.annotations(for: symbolID)
        guard !annotations.isEmpty else {
            return []
        }

        let sourceFile = sourceFile(for: symbolID, ctx: ctx)
        let cacheKey = OptInResolutionCache.RequirementsKey(
            symbolID: symbolID,
            fileID: sourceFile?.fileID
        )
        if let cached = optInResolutionCache.requirementsBySymbol[cacheKey] {
            return cached
        }

        var requirements: [OptInRequirement] = []
        var seenMarkers: Set<SymbolID> = []

        // Only a marker directly applied to an API propagates to its callers.
        // An experimental annotation's own marker is checked at its application,
        // type and constructor sites, not at uses of the annotated declaration.
        for annotation in annotations {
            guard let annotationSymbol = resolveAnnotationClassSymbol(
                named: annotation.annotationFQName,
                file: sourceFile,
                ctx: ctx
            ) else {
                continue
            }

            if let requirement = optInRequirement(forMarkerAnnotation: annotationSymbol, ctx: ctx),
               seenMarkers.insert(requirement.markerSymbol).inserted
            {
                requirements.append(requirement)
            }


        }

        optInResolutionCache.requirementsBySymbol[cacheKey] = requirements
        return requirements
    }

    private func optInRequirement(
        forMarkerAnnotation markerSymbol: SymbolID,
        ctx: TypeInferenceContext
    ) -> OptInRequirement? {
        for metaAnnotation in ctx.sema.symbols.annotations(for: markerSymbol)
            where KnownCompilerAnnotation.requiresOptIn.matches(metaAnnotation.annotationFQName)
        {
            let parsed = parseRequiresOptInArguments(metaAnnotation.arguments)
            let markerName = renderSymbolName(markerSymbol, ctx: ctx)
            return OptInRequirement(
                markerSymbol: markerSymbol,
                markerName: markerName,
                message: parsed.message,
                level: parsed.level
            )
        }
        return nil
    }

    private func validateSubclassOptInRequirement(
        _ annotation: MetadataAnnotationRecord,
        inheritedFrom supertype: SymbolID,
        optedInMarkers: Set<SymbolID>,
        ctx: TypeInferenceContext,
        range: SourceRange?,
        diagnostics: DiagnosticEngine
    ) {
        let markerNames = parseOptInMarkerNames(annotation.arguments)
        if markerNames.isEmpty {
            // An argument that names no marker at all must not silently become
            // a no-op. An empty 'markerClass' vararg is legal Kotlin and
            // imposes no requirement.
            if !annotation.arguments.isEmpty {
                diagnostics.error(
                    "KSWIFTK-SEMA-SUBCLASS-OPT-IN",
                    "'@SubclassOptInRequired' markerClass must reference an opt-in marker annotation.",
                    range: range
                )
            }
            return
        }

        // 'markerClass' is a vararg: kotlinc checks every entry and requires
        // opt-in to each listed marker, not just the first.
        let markerFile = sourceFile(for: supertype, ctx: ctx) ?? currentFile(in: ctx)
        for markerName in markerNames {
            guard let markerSymbol = resolveAnnotationClassSymbol(
                named: markerName,
                file: markerFile,
                ctx: ctx
            ), let requirement = optInRequirement(forMarkerAnnotation: markerSymbol, ctx: ctx)
            else {
                diagnostics.error(
                    "KSWIFTK-SEMA-SUBCLASS-OPT-IN",
                    "'@SubclassOptInRequired' markerClass must reference an opt-in marker annotation.",
                    range: range
                )
                continue
            }

            guard !optedInMarkers.contains(requirement.markerSymbol) else {
                continue
            }

            let supertypeName = renderSymbolName(supertype, ctx: ctx)
            let messageSuffix = requirement.message.isEmpty ? "" : " \(requirement.message)"
            let message = "Subclassing '\(supertypeName)' requires opt-in to '\(requirement.markerName)'. " +
                "Annotate the subclass with '@\(requirement.markerName)', '@OptIn(\(requirement.markerName)::class)' or '@SubclassOptInRequired(\(requirement.markerName)::class)'." + messageSuffix
            switch requirement.level {
            case .warning:
                diagnostics.warning("KSWIFTK-SEMA-SUBCLASS-OPT-IN", message, range: range)
            case .error:
                diagnostics.error("KSWIFTK-SEMA-SUBCLASS-OPT-IN", message, range: range)
            }
        }
    }

    func primaryConstructorParameterOptInContext(
        _ parameter: ValueParamDecl,
        ctx: TypeInferenceContext
    ) -> TypeInferenceContext {
        var parameterCtx = ctx
        if let file = currentFile(in: ctx) {
            let annotations = parameter.annotations.compactMap { annotation -> MetadataAnnotationRecord? in
                guard annotation.useSiteTarget == nil || annotation.useSiteTarget?.lowercased() == "param",
                      let symbol = resolveAnnotationSymbol(
                          named: annotation.name, in: file, symbols: ctx.sema.symbols,
                          interner: ctx.interner, types: ctx.sema.types,
                          enclosingSymbol: ctx.currentDeclSymbol
                      ), let info = ctx.sema.symbols.symbol(symbol),
                      info.fqName.map(ctx.interner.resolve).joined(separator: ".") == KnownCompilerAnnotation.optIn.qualifiedName
                else { return nil }
                return MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.optIn.qualifiedName,
                    arguments: annotation.arguments
                )
            }
            collectOptInMarkers(
                from: annotations, file: file, ctx: ctx, into: &parameterCtx.inheritedOptInMarkers
            )
        }
        return parameterCtx
    }

    func checkPrimaryConstructorPropertyHeaderOptIn(
        parameter: ValueParamDecl,
        parameterType: TypeID,
        propertyType: TypeID,
        constructor: SymbolID,
        ctx: TypeInferenceContext,
        range: SourceRange?
    ) {
        let parameterCtx = primaryConstructorParameterOptInContext(
            parameter, ctx: ctx.with(currentDeclSymbol: constructor)
        )
        var propertyCtx = ctx
        propertyCtx.inheritedOptInMarkers.formUnion(parameterCtx.inheritedOptInMarkers)
        // A property-site opt-in cannot authorize the original parameter type.
        // De-duplicate shared markers across this pair without merging their
        // permission contexts. A vararg's implicit array belongs to its parameter.
        let parameterRequirements = requiredOptInRequirements(
            forTypes: [parameterType], ctx: parameterCtx
        )
        emitOptInRequirements(
            parameterRequirements, ctx: parameterCtx, range: range, diagnostics: ctx.sema.diagnostics
        )
        let parameterMarkers = Set(parameterRequirements.map(\.markerSymbol))
        let propertyRequirements = requiredOptInRequirements(
            forTypes: [propertyType], ctx: propertyCtx
        ).filter { !parameterMarkers.contains($0.markerSymbol) }
        emitOptInRequirements(
            propertyRequirements, ctx: propertyCtx, range: range, diagnostics: ctx.sema.diagnostics
        )
    }

    func accessorOptInContext(
        annotations: [AnnotationNode],
        ctx: TypeInferenceContext
    ) -> TypeInferenceContext {
        guard !annotations.isEmpty, let file = currentFile(in: ctx) else { return ctx }
        var copy = ctx
        collectOptInMarkers(
            from: annotations.filter { KnownCompilerAnnotation.optIn.matches($0.name) },
            file: file, ctx: ctx, into: &copy.accessorOptInMarkers
        )
        return copy
    }

    func localFunctionOptInContext(_ ctx: TypeInferenceContext) -> TypeInferenceContext {
        var copy = ctx
        // A local extension changes currentDeclSymbol for receiver resolution,
        // but its body still inherits the enclosing declaration's opt-ins.
        copy.inheritedOptInMarkers = activeOptInMarkers(in: ctx)
        return copy
    }

    private func activeOptInMarkers(in ctx: TypeInferenceContext) -> Set<SymbolID> {
        var markers = ctx.accessorOptInMarkers.union(ctx.inheritedOptInMarkers)
        let file = currentFile(in: ctx)

        for markerName in ctx.globalOptInMarkerNames {
            if let markerSymbol = resolveAnnotationClassSymbol(
                named: markerName,
                file: file,
                ctx: ctx
            ) {
                markers.insert(markerSymbol)
            }
        }

        if let file {
            collectOptInMarkers(
                from: file.annotations,
                file: file,
                ctx: ctx,
                into: &markers
            )
        }

        var symbol = ctx.currentDeclSymbol
        while let current = symbol {
            collectOptInMarkers(
                from: ctx.sema.symbols.annotations(for: current),
                file: sourceFile(for: current, ctx: ctx) ?? currentFile(in: ctx),
                ctx: ctx,
                into: &markers
            )
            symbol = ctx.sema.symbols.parentSymbol(for: current)
        }

        return markers
    }

    private func collectOptInMarkers(
        from annotations: [MetadataAnnotationRecord],
        file: ASTFile?,
        ctx: TypeInferenceContext,
        into markers: inout Set<SymbolID>
    ) {
        for annotation in annotations {
            if KnownCompilerAnnotation.optIn.matches(annotation.annotationFQName) {
                for markerName in parseOptInMarkerNames(annotation.arguments) {
                    if let markerSymbol = resolveAnnotationClassSymbol(
                        named: markerName,
                        file: file,
                        ctx: ctx
                    ) {
                        markers.insert(markerSymbol)
                    }
                }
            }

            // If this annotation is itself a @RequiresOptIn marker, it implicitly
            // grants opt-in for that marker within the annotated declaration's scope.
            if let annotationSymbol = resolveAnnotationClassSymbol(
                named: annotation.annotationFQName,
                file: file,
                ctx: ctx
            ),
               optInRequirement(forMarkerAnnotation: annotationSymbol, ctx: ctx) != nil
            {
                markers.insert(annotationSymbol)
            }
        }

        for annotation in annotations {
            guard let markerAnnotation = resolveAnnotationClassSymbol(
                named: annotation.annotationFQName,
                file: file,
                ctx: ctx
            ),
            let requirement = optInRequirement(forMarkerAnnotation: markerAnnotation, ctx: ctx)
            else {
                continue
            }
            markers.insert(requirement.markerSymbol)
        }
    }

    private func collectOptInMarkers(
        from annotations: [AnnotationNode],
        file: ASTFile,
        ctx: TypeInferenceContext,
        into markers: inout Set<SymbolID>
    ) {
        for annotation in annotations {
            if KnownCompilerAnnotation.optIn.matches(annotation.name) {
                for markerName in parseOptInMarkerNames(annotation.arguments) {
                    if let markerSymbol = resolveAnnotationClassSymbol(
                        named: markerName,
                        file: file,
                        ctx: ctx
                    ) {
                        markers.insert(markerSymbol)
                    }
                }
            }

            // If this annotation is itself a @RequiresOptIn marker, it implicitly
            // grants opt-in for that marker within the annotated declaration's scope.
            if let annotationSymbol = resolveAnnotationClassSymbol(
                named: annotation.name,
                file: file,
                ctx: ctx
            ),
               optInRequirement(forMarkerAnnotation: annotationSymbol, ctx: ctx) != nil
            {
                markers.insert(annotationSymbol)
            }
        }
    }

    private func parseRequiresOptInArguments(
        _ arguments: [String]
    ) -> (message: String, level: OptInLevel) {
        var namedArgs: [String: String] = [:]
        var positionalArgs: [String] = []

        for raw in arguments {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            if let (name, value) = splitOptInNamedArgument(trimmed) {
                namedArgs[name.lowercased()] = value
            } else {
                positionalArgs.append(trimmed)
            }
        }

        let message = normalizeAnnotationStringLiteral(namedArgs["message"] ?? positionalArgs.first ?? "")
        let levelCandidate = namedArgs["level"] ?? positionalArgs.first(where: { parseOptInLevel($0) != nil })
        return (
            message: message,
            level: parseOptInLevel(levelCandidate) ?? .error
        )
    }

    private func parseOptInLevel(_ raw: String?) -> OptInLevel? {
        guard var raw else {
            return nil
        }
        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        raw = normalizeAnnotationStringLiteral(raw)
        let normalized = raw.replacingOccurrences(of: " ", with: "")
        let levelName = normalized.split(separator: ".").last.map(String.init)?.uppercased() ?? normalized.uppercased()
        return switch levelName {
        case "WARNING":
            .warning
        case "ERROR":
            .error
        default:
            nil
        }
    }

    private func parseOptInMarkerNames(_ arguments: [String]) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []
        let regex = OptInMarkerClassParser.classReferenceRegex

        for argument in arguments {
            let value = SemaAnnotationArgument.value(argument)
            let nsValue = value as NSString
            let matches = regex.matches(
                in: value,
                range: NSRange(location: 0, length: nsValue.length)
            )
            for match in matches {
                let rawMatch = nsValue.substring(with: match.range)
                let trimmed = rawMatch
                    .replacingOccurrences(of: "::class", with: "")
                    .replacingOccurrences(of: ":: class", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]()"))
                guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                    continue
                }
                names.append(trimmed)
            }

            if matches.isEmpty,
               let normalized = normalizeOptInMarkerName(value),
               seen.insert(normalized).inserted
            {
                names.append(normalized)
            }
        }

        return names
    }

    private func normalizeOptInMarkerName(_ raw: String) -> String? {
        let trimmed = SemaAnnotationArgument.value(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]()"))
        guard !trimmed.isEmpty else {
            return nil
        }

        let suffixes = ["::class", ".class", ":class", "class"]
        for suffix in suffixes where trimmed.count > suffix.count && trimmed.hasSuffix(suffix) {
            return String(trimmed.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private func splitOptInNamedArgument(_ argument: String) -> (String, String)? {
        guard let equalIndex = argument.firstIndex(of: "=") else {
            return nil
        }
        let name = String(argument[..<equalIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(argument[argument.index(after: equalIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !value.isEmpty else {
            return nil
        }
        return (name, value)
    }



    private func resolveAnnotationClassSymbol(
        named rawName: String,
        file: ASTFile?,
        ctx: TypeInferenceContext
    ) -> SymbolID? {
        let cacheKey = OptInResolutionCache.AnnotationClassKey(
            rawName: rawName,
            fileID: file?.fileID
        )
        if let cached = optInResolutionCache.annotationClassSymbols[cacheKey] {
            return cached
        }
        let resolved = uncachedAnnotationClassSymbol(named: rawName, file: file, ctx: ctx)
        optInResolutionCache.annotationClassSymbols[cacheKey] = resolved
        return resolved
    }

    private func uncachedAnnotationClassSymbol(
        named rawName: String,
        file: ASTFile?,
        ctx: TypeInferenceContext
    ) -> SymbolID? {
        let parts = rawName
            .split(separator: ".")
            .map(String.init)
            .filter { !$0.isEmpty }

        if parts.count > 1 {
            let fqName = parts.map { ctx.interner.intern($0) }
            if let symbol = ctx.sema.symbols.lookup(fqName: fqName),
               ctx.sema.symbols.symbol(symbol)?.kind == .annotationClass
            {
                return symbol
            }
        }

        guard let shortPart = parts.last ?? rawName.split(separator: ".").last.map(String.init) else {
            return nil
        }
        let shortName = ctx.interner.intern(shortPart)

        if let file {
            let samePackageFQName = file.packageFQName + [shortName]
            if let symbol = ctx.sema.symbols.lookup(fqName: samePackageFQName),
               ctx.sema.symbols.symbol(symbol)?.kind == .annotationClass
            {
                return symbol
            }

            for importDecl in file.imports {
                if let alias = importDecl.alias, alias == shortName,
                   let symbol = ctx.sema.symbols.lookup(fqName: importDecl.path),
                   ctx.sema.symbols.symbol(symbol)?.kind == .annotationClass
                {
                    return symbol
                }

                if importDecl.path.last == shortName,
                   let symbol = ctx.sema.symbols.lookup(fqName: importDecl.path),
                   ctx.sema.symbols.symbol(symbol)?.kind == .annotationClass
                {
                    return symbol
                }
            }
        }

        return ctx.sema.symbols.lookupByShortName(shortName).first {
            ctx.sema.symbols.symbol($0)?.kind == .annotationClass
        }
    }

    private func currentFile(in ctx: TypeInferenceContext) -> ASTFile? {
        ctx.ast.file(for: ctx.currentFileID)
    }

    private func sourceFile(
        for symbolID: SymbolID,
        ctx: TypeInferenceContext
    ) -> ASTFile? {
        guard let fileID = ctx.sema.symbols.sourceFileID(for: symbolID) else {
            return currentFile(in: ctx)
        }
        return ctx.ast.file(for: fileID)
    }

    private func renderSymbolName(_ symbolID: SymbolID, ctx: TypeInferenceContext) -> String {
        guard let symbol = ctx.sema.symbols.symbol(symbolID) else {
            return "<unknown>"
        }
        return symbol.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
    }

    private func typeArgType(_ arg: TypeArg) -> TypeID? {
        switch arg {
        case .invariant(let type), .in(let type), .out(let type):
            type
        case .star:
            nil
        }
    }
}

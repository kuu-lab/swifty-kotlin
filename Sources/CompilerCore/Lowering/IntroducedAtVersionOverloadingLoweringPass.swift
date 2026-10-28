/// Emits older ABI entry points for declarations whose optional parameters
/// carry `@IntroducedAt` versions. The wrappers keep the original default
/// expressions reachable through the declaration's `$default` stub.
final class IntroducedAtVersionOverloadingLoweringPass: LoweringPass {
    static let name = "IntroducedAtVersionOverloading"
    static let requiredStage: KIRStage = .desugared
    static let producedStage: KIRStage = .desugared

    private struct OverloadPlan: Equatable {
        let valueParameterIndices: [Int]
        let preservesDefaultValues: Bool
    }

    private struct FunctionParameterLayout {
        let prefixParameters: [KIRParameter]
        let valueParameters: [KIRParameter]
        let reifiedTokenParameters: [KIRParameter]
    }

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        guard let sema = ctx.sema else { return false }
        return module.arena.declarations.contains { decl in
            guard case let .function(function) = decl else { return false }
            return overloadPlans(for: function, symbols: sema.symbols) != nil
        }
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }

        let symbols = sema.symbols
        let arena = module.arena
        let originalDecls = arena.declarations
        let unitType = sema.types.unitType
        let longType = sema.types.make(.primitive(.long, .nonNull))

        for decl in originalDecls {
            guard case let .function(function) = decl,
                  let functionInfo = symbols.symbol(function.symbol),
                  let signature = symbols.functionSignature(for: function.symbol),
                  let plans = overloadPlans(for: function, symbols: symbols),
                  let layout = parameterLayout(for: function, signature: signature)
            else {
                continue
            }

            for plan in plans {
                let wrapperParameters = layout.prefixParameters
                    + plan.valueParameterIndices.map { layout.valueParameters[$0] }
                    + layout.reifiedTokenParameters
                let wrapperFlags = functionInfo.flags.union(.synthetic)
                let wrapperSymbol = symbols.define(
                    kind: functionInfo.kind,
                    name: function.name,
                    fqName: functionInfo.fqName,
                    declSite: functionInfo.declSite,
                    visibility: functionInfo.visibility,
                    flags: wrapperFlags
                )
                guard wrapperSymbol != function.symbol else { continue }

                if let parentSymbol = symbols.parentSymbol(for: function.symbol) {
                    symbols.setParentSymbol(parentSymbol, for: wrapperSymbol)
                }

                let wrapperSignature = makeSignature(
                    for: plan,
                    original: signature
                )
                symbols.setFunctionSignature(wrapperSignature, for: wrapperSymbol)

                let wrapperAnnotations = symbols.annotations(for: function.symbol).filter {
                    !KnownCompilerAnnotation.jvmOverloads.matches($0.annotationFQName)
                }
                if !wrapperAnnotations.isEmpty {
                    symbols.setAnnotations(wrapperAnnotations, for: wrapperSymbol)
                }

                let wrapperBody = buildWrapperBody(
                    function: function,
                    signature: signature,
                    layout: layout,
                    retainedValueParameterIndices: plan.valueParameterIndices,
                    unitType: unitType,
                    longType: longType,
                    arena: arena,
                    interner: ctx.interner
                )

                _ = arena.appendDecl(.function(KIRFunction(
                    symbol: wrapperSymbol,
                    name: function.name,
                    params: wrapperParameters,
                    returnType: function.returnType,
                    body: wrapperBody,
                    isSuspend: function.isSuspend,
                    isInline: function.isInline,
                    isInlineOnly: function.isInlineOnly,
                    isTailrec: function.isTailrec,
                    sourceRange: function.sourceRange
                )))

                guard plan.preservesDefaultValues,
                      wrapperSignature.valueParameterHasDefaultValues.contains(true)
                else {
                    continue
                }

                let defaultStub = buildDefaultStub(
                    function: function,
                    wrapperSymbol: wrapperSymbol,
                    signature: signature,
                    layout: layout,
                    retainedValueParameterIndices: plan.valueParameterIndices,
                    longType: longType,
                    arena: arena,
                    symbols: symbols,
                    interner: ctx.interner
                )
                _ = arena.appendDecl(.function(defaultStub))
            }
        }

        module.recordLowering(Self.name)
    }

    private func overloadPlans(for function: KIRFunction, symbols: SymbolTable) -> [OverloadPlan]? {
        guard let functionInfo = symbols.symbol(function.symbol),
              !functionInfo.flags.contains(.synthetic),
              functionInfo.kind == .function || functionInfo.kind == .constructor,
              let signature = symbols.functionSignature(for: function.symbol),
              symbols.overrideDefaultsBaseSymbol(for: function.symbol) == nil
        else {
            return nil
        }

        let parameterCount = signature.parameterTypes.count
        guard signature.valueParameterSymbols.count == parameterCount else { return nil }

        var versionByIndex: [Int: ComparableVersion] = [:]
        for (index, parameterSymbol) in signature.valueParameterSymbols.enumerated() {
            guard let annotation = symbols.annotations(for: parameterSymbol).first(where: {
                KnownCompilerAnnotation.introducedAt.matches($0.annotationFQName)
            }) else {
                continue
            }
            guard let sourceVersion = annotation.arguments.first else { return nil }

            let hasDefault = signature.valueParameterHasDefaultValues.indices.contains(index)
                && signature.valueParameterHasDefaultValues[index]
            let isVararg = signature.valueParameterIsVararg.indices.contains(index)
                && signature.valueParameterIsVararg[index]
            guard hasDefault, !isVararg else { return nil }
            versionByIndex[index] = ComparableVersion(annotationStringValue(sourceVersion))
        }
        guard !versionByIndex.isEmpty else { return nil }

        var versions: [ComparableVersion] = []
        for version in versionByIndex.values where !versions.contains(version) {
            versions.append(version)
        }
        versions.sort()

        var thresholds: [ComparableVersion?] = [nil]
        thresholds.append(contentsOf: versions.dropLast().map(Optional.some))

        var plans: [OverloadPlan] = []
        for threshold in thresholds {
            let retainedIndices = (0 ..< parameterCount).filter { index in
                guard let version = versionByIndex[index] else { return true }
                guard let threshold else { return false }
                return version <= threshold
            }

            // In valid Kotlin declarations, versioned optional parameters are
            // ordered before any trailing required lambda. This keeps the
            // mask positions for retained defaults aligned with their source
            // parameter positions in the generated older `$default` ABI.
            let retainsStableDefaultIndices = retainedIndices.enumerated().allSatisfy { wrapperIndex, sourceIndex in
                let hasDefault = signature.valueParameterHasDefaultValues.indices.contains(sourceIndex)
                    && signature.valueParameterHasDefaultValues[sourceIndex]
                return !hasDefault || wrapperIndex == sourceIndex
            }
            guard retainsStableDefaultIndices else { continue }
            plans.append(OverloadPlan(valueParameterIndices: retainedIndices, preservesDefaultValues: true))
        }

        if symbols.annotations(for: function.symbol).contains(where: {
            KnownCompilerAnnotation.jvmOverloads.matches($0.annotationFQName)
        }) {
            plans.append(contentsOf: jvmOverloadPlans(for: signature))
        }

        var uniquePlans: [OverloadPlan] = []
        for plan in plans {
            if let existingIndex = uniquePlans.firstIndex(where: {
                $0.valueParameterIndices == plan.valueParameterIndices
            }) {
                if plan.preservesDefaultValues && !uniquePlans[existingIndex].preservesDefaultValues {
                    uniquePlans[existingIndex] = plan
                }
            } else {
                uniquePlans.append(plan)
            }
        }
        return uniquePlans.isEmpty ? nil : uniquePlans
    }

    private func jvmOverloadPlans(for signature: FunctionSignature) -> [OverloadPlan] {
        let defaults = signature.valueParameterHasDefaultValues
        guard !defaults.isEmpty, defaults.contains(true) else { return [] }

        var trailingDefaultCount = 0
        for hasDefault in defaults.reversed() {
            if hasDefault {
                trailingDefaultCount += 1
            } else {
                break
            }
        }
        guard trailingDefaultCount > 0 else { return [] }

        let firstDefaultIndex = signature.parameterTypes.count - trailingDefaultCount
        return (firstDefaultIndex ..< signature.parameterTypes.count).reversed().map { keepCount in
            OverloadPlan(
                valueParameterIndices: Array(0 ..< keepCount),
                preservesDefaultValues: false
            )
        }
    }

    private func parameterLayout(
        for function: KIRFunction,
        signature: FunctionSignature
    ) -> FunctionParameterLayout? {
        let reifiedTokenCount = function.isInline ? signature.reifiedTypeParameterIndices.count * 2 : 0
        let prefixCount = function.params.count - signature.parameterTypes.count - reifiedTokenCount
        guard prefixCount >= 0,
              function.params.count >= reifiedTokenCount,
              prefixCount + signature.parameterTypes.count + reifiedTokenCount == function.params.count
        else {
            return nil
        }

        return FunctionParameterLayout(
            prefixParameters: Array(function.params.prefix(prefixCount)),
            valueParameters: Array(function.params.dropFirst(prefixCount).prefix(signature.parameterTypes.count)),
            reifiedTokenParameters: reifiedTokenCount == 0
                ? []
                : Array(function.params.suffix(reifiedTokenCount))
        )
    }

    private func makeSignature(for plan: OverloadPlan, original: FunctionSignature) -> FunctionSignature {
        let indices = plan.valueParameterIndices
        return FunctionSignature(
            receiverType: original.receiverType,
            contextReceiverTypes: original.contextReceiverTypes,
            contextParameterSymbols: original.contextParameterSymbols,
            contextParameterTypes: original.contextParameterTypes,
            parameterTypes: indices.map { original.parameterTypes[$0] },
            returnType: original.returnType,
            isSuspend: original.isSuspend,
            canThrow: original.canThrow,
            valueParameterSymbols: indices.map { original.valueParameterSymbols[$0] },
            valueParameterUnsafeVarianceTypeParameterSymbols: indices.compactMap {
                original.valueParameterUnsafeVarianceTypeParameterSymbols.indices.contains($0)
                    ? original.valueParameterUnsafeVarianceTypeParameterSymbols[$0]
                    : nil
            },
            valueParameterHasDefaultValues: indices.map { index in
                plan.preservesDefaultValues
                    && original.valueParameterHasDefaultValues.indices.contains(index)
                    && original.valueParameterHasDefaultValues[index]
            },
            valueParameterIsVararg: indices.map { index in
                original.valueParameterIsVararg.indices.contains(index)
                    && original.valueParameterIsVararg[index]
            },
            valueParameterAllowsNonLocalReturn: indices.map { index in
                original.valueParameterAllowsNonLocalReturn.indices.contains(index)
                    && original.valueParameterAllowsNonLocalReturn[index]
            },
            hasExplicitInlineParameterMetadata: original.hasExplicitInlineParameterMetadata,
            typeParameterSymbols: original.typeParameterSymbols,
            reifiedTypeParameterIndices: original.reifiedTypeParameterIndices,
            typeParameterUpperBounds: original.typeParameterUpperBounds,
            typeParameterUpperBoundsList: original.typeParameterUpperBoundsList,
            classTypeParameterCount: original.classTypeParameterCount
        )
    }

    private func buildWrapperBody(
        function: KIRFunction,
        signature: FunctionSignature,
        layout: FunctionParameterLayout,
        retainedValueParameterIndices: [Int],
        unitType: TypeID,
        longType: TypeID,
        arena: KIRArena,
        interner: StringInterner
    ) -> [KIRInstruction] {
        var body: [KIRInstruction] = [.beginBlock]
        var forwardedArguments: [KIRExprID] = []

        for parameter in layout.prefixParameters {
            forwardedArguments.append(appendParameterReference(parameter, arena: arena, body: &body))
        }

        var valueArguments: [Int: KIRExprID] = [:]
        for parameter in retainedValueParameterIndices {
            let expression = appendParameterReference(
                layout.valueParameters[parameter], arena: arena, body: &body
            )
            valueArguments[parameter] = expression
        }

        var defaultMask = DefaultArgumentMask(parameterCount: signature.parameterTypes.count)
        for index in signature.parameterTypes.indices {
            if let expression = valueArguments[index] {
                forwardedArguments.append(expression)
            } else {
                let sentinel = arena.appendExpr(.intLiteral(0), type: signature.parameterTypes[index])
                body.append(.constValue(result: sentinel, value: .intLiteral(0)))
                forwardedArguments.append(sentinel)
                defaultMask.insert(index)
            }
        }

        for tokenParameter in layout.reifiedTokenParameters {
            forwardedArguments.append(appendParameterReference(tokenParameter, arena: arena, body: &body))
        }
        for mask in defaultMask.stubWords {
            let maskExpr = arena.appendExpr(.intLiteral(mask), type: longType)
            body.append(.constValue(result: maskExpr, value: .intLiteral(mask)))
            forwardedArguments.append(maskExpr)
        }

        let stubSymbol = SyntheticSymbolScheme.defaultStubSymbol(for: function.symbol)
        let stubName = interner.intern(interner.resolve(function.name) + "$default")
        if function.returnType == unitType {
            body.append(.call(
                symbol: stubSymbol,
                callee: stubName,
                arguments: forwardedArguments,
                result: nil,
                canThrow: signature.canThrow
            ))
            body.append(.returnUnit)
        } else {
            let callResult = arena.appendTemporary(type: function.returnType)
            body.append(.call(
                symbol: stubSymbol,
                callee: stubName,
                arguments: forwardedArguments,
                result: callResult,
                canThrow: signature.canThrow
            ))
            body.append(.returnValue(callResult))
        }

        body.append(.endBlock)
        return body
    }

    private func buildDefaultStub(
        function: KIRFunction,
        wrapperSymbol: SymbolID,
        signature: FunctionSignature,
        layout: FunctionParameterLayout,
        retainedValueParameterIndices: [Int],
        longType: TypeID,
        arena: KIRArena,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> KIRFunction {
        let wrapperValueParameters = retainedValueParameterIndices.map { layout.valueParameters[$0] }
        let wrapperMaskWords = DefaultArgumentMask(parameterCount: retainedValueParameterIndices.count)
        let wrapperMaskParameters = maskParameters(
            for: wrapperSymbol,
            wordCount: wrapperMaskWords.stubWords.count,
            longType: longType,
            symbols: symbols,
            interner: interner
        )
        let stubParameters = layout.prefixParameters
            + wrapperValueParameters
            + layout.reifiedTokenParameters
            + wrapperMaskParameters

        var body: [KIRInstruction] = [.beginBlock]
        var forwardedArguments: [KIRExprID] = []
        for parameter in layout.prefixParameters {
            forwardedArguments.append(appendParameterReference(parameter, arena: arena, body: &body))
        }

        var valueArguments: [Int: KIRExprID] = [:]
        for (wrapperIndex, sourceIndex) in retainedValueParameterIndices.enumerated() {
            let expression = appendParameterReference(
                wrapperValueParameters[wrapperIndex], arena: arena, body: &body
            )
            valueArguments[sourceIndex] = expression
        }

        var omittedMask = DefaultArgumentMask(parameterCount: signature.parameterTypes.count)
        for index in signature.parameterTypes.indices {
            if let expression = valueArguments[index] {
                forwardedArguments.append(expression)
            } else {
                let sentinel = arena.appendExpr(.intLiteral(0), type: signature.parameterTypes[index])
                body.append(.constValue(result: sentinel, value: .intLiteral(0)))
                forwardedArguments.append(sentinel)
                omittedMask.insert(index)
            }
        }

        for tokenParameter in layout.reifiedTokenParameters {
            forwardedArguments.append(appendParameterReference(tokenParameter, arena: arena, body: &body))
        }

        var incomingMaskExpressions: [KIRExprID] = []
        for parameter in wrapperMaskParameters {
            incomingMaskExpressions.append(appendParameterReference(parameter, arena: arena, body: &body))
        }

        let originalMaskWordCount = omittedMask.words.count
        let wrapperMaskWordCount = wrapperMaskWords.words.count
        for wordIndex in omittedMask.stubWords.indices {
            let dynamicMask = wordIndex < originalMaskWordCount
                && wordIndex < wrapperMaskWordCount
                ? incomingMaskExpressions[wordIndex]
                : nil
            let fixedMask = omittedMask.stubWords[wordIndex]

            if let dynamicMask, fixedMask != 0 {
                let fixedExpr = arena.appendExpr(.intLiteral(fixedMask), type: longType)
                body.append(.constValue(result: fixedExpr, value: .intLiteral(fixedMask)))
                let combined = arena.appendTemporary(type: longType)
                body.append(.call(
                    callee: interner.intern("kk_bitwise_or"),
                    arguments: [dynamicMask, fixedExpr],
                    result: combined,
                    canThrow: false
                ))
                forwardedArguments.append(combined)
            } else if let dynamicMask {
                forwardedArguments.append(dynamicMask)
            } else {
                let maskExpr = arena.appendExpr(.intLiteral(fixedMask), type: longType)
                body.append(.constValue(result: maskExpr, value: .intLiteral(fixedMask)))
                forwardedArguments.append(maskExpr)
            }
        }

        let sourceStubSymbol = SyntheticSymbolScheme.defaultStubSymbol(for: function.symbol)
        let stubName = interner.intern(interner.resolve(function.name) + "$default")
        let result = arena.appendTemporary(type: function.returnType)
        body.append(.call(
            symbol: sourceStubSymbol,
            callee: stubName,
            arguments: forwardedArguments,
            result: result,
            canThrow: signature.canThrow
        ))
        body.append(.returnValue(result))
        body.append(.endBlock)

        let wrapperInfo = symbols.symbol(wrapperSymbol)
        let wrapperName = interner.intern(interner.resolve(wrapperInfo?.name ?? function.name) + "$default")
        return KIRFunction(
            symbol: SyntheticSymbolScheme.defaultStubSymbol(for: wrapperSymbol),
            name: wrapperName,
            params: stubParameters,
            returnType: function.returnType,
            body: body,
            isSuspend: function.isSuspend,
            isInline: function.isInline
        )
    }

    private func maskParameters(
        for wrapperSymbol: SymbolID,
        wordCount: Int,
        longType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [KIRParameter] {
        guard wordCount > 0,
              let wrapperInfo = symbols.symbol(wrapperSymbol)
        else {
            return []
        }

        return (0 ..< wordCount).map { index in
            let symbol: SymbolID
            if index == 0 {
                symbol = SyntheticSymbolScheme.defaultMaskSymbol(for: wrapperSymbol)
            } else {
                let parameterName = interner.intern("__default_mask_\(wrapperSymbol.rawValue)_\(index)")
                symbol = symbols.define(
                    kind: .valueParameter,
                    name: parameterName,
                    fqName: wrapperInfo.fqName + [parameterName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
            }
            return KIRParameter(symbol: symbol, type: longType)
        }
    }

    private func appendParameterReference(
        _ parameter: KIRParameter,
        arena: KIRArena,
        body: inout [KIRInstruction]
    ) -> KIRExprID {
        let expression = arena.appendExpr(.symbolRef(parameter.symbol), type: parameter.type)
        body.append(.constValue(result: expression, value: .symbolRef(parameter.symbol)))
        return expression
    }

    private func annotationStringValue(_ source: String) -> String {
        guard source.count >= 2,
              source.first == "\"",
              source.last == "\""
        else {
            return source
        }
        return String(source.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

private struct ComparableVersion: Comparable, Equatable {
    private enum Token: Equatable {
        case number(String)
        case qualifier(String)
    }

    private let tokens: [Token]

    init(_ source: String) {
        var parsed: [Token] = []
        var current = ""
        var currentIsNumber: Bool?

        func appendCurrent() {
            guard !current.isEmpty, let currentIsNumber else { return }
            if currentIsNumber {
                parsed.append(.number(Self.normalizedNumber(current)))
            } else {
                parsed.append(.qualifier(Self.normalizedQualifier(current)))
            }
            current = ""
        }

        for character in source.lowercased() {
            if character.isNumber {
                if currentIsNumber == false { appendCurrent() }
                currentIsNumber = true
                current.append(character)
            } else if character.isLetter {
                if currentIsNumber == true { appendCurrent() }
                currentIsNumber = false
                current.append(character)
            } else {
                appendCurrent()
                currentIsNumber = nil
            }
        }
        appendCurrent()
        tokens = parsed
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        compare(lhs.tokens, rhs.tokens) == 0
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        compare(lhs.tokens, rhs.tokens) < 0
    }

    private static func compare(_ lhs: [Token], _ rhs: [Token]) -> Int {
        let count = max(lhs.count, rhs.count)
        for index in 0 ..< count {
            let left = index < lhs.count ? lhs[index] : nil
            let right = index < rhs.count ? rhs[index] : nil
            let result: Int

            switch (left, right) {
            case let (.some(left), .some(right)):
                result = compare(left, right)
            case let (.some(left), .none):
                result = compare(left, implicitDefault(for: left))
            case let (.none, .some(right)):
                result = -compare(right, implicitDefault(for: right))
            case (.none, .none):
                result = 0
            }

            if result != 0 { return result }
        }
        return 0
    }

    private static func compare(_ lhs: Token, _ rhs: Token) -> Int {
        switch (lhs, rhs) {
        case let (.number(left), .number(right)):
            if left.count != right.count { return left.count < right.count ? -1 : 1 }
            if left == right { return 0 }
            return left < right ? -1 : 1
        case (.number, .qualifier):
            return 1
        case (.qualifier, .number):
            return -1
        case let (.qualifier(left), .qualifier(right)):
            let leftRank = qualifierRank(left)
            let rightRank = qualifierRank(right)
            if leftRank != rightRank { return leftRank < rightRank ? -1 : 1 }
            if left == right { return 0 }
            return left < right ? -1 : 1
        }
    }

    private static func implicitDefault(for token: Token) -> Token {
        switch token {
        case .number:
            .number("0")
        case .qualifier:
            .qualifier("")
        }
    }

    private static func normalizedNumber(_ source: String) -> String {
        let stripped = source.drop(while: { $0 == "0" })
        return stripped.isEmpty ? "0" : String(stripped)
    }

    private static func normalizedQualifier(_ source: String) -> String {
        switch source {
        case "a": "alpha"
        case "b": "beta"
        case "m": "milestone"
        case "cr": "rc"
        case "ga", "final", "release": ""
        default: source
        }
    }

    private static func qualifierRank(_ qualifier: String) -> Int {
        switch qualifier {
        case "alpha": 0
        case "beta": 1
        case "milestone": 2
        case "rc": 3
        case "snapshot": 4
        case "": 5
        case "sp": 6
        default: 4
        }
    }
}

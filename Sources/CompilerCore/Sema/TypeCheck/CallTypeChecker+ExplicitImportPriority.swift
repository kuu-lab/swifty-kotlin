extension CallTypeChecker {
    /// Kotlin checks explicit top-level imports before same-package functions.
    /// Keep the import tier when it has an applicable candidate so a more
    /// specific same-package overload cannot outrank it during final selection.
    func preferApplicableExplicitTopLevelImportTier(
        candidates: [SymbolID],
        args: [CallArgument],
        argTypes: [TypeID],
        range: SourceRange,
        calleeName: InternedString?,
        explicitTypeArgs: [TypeID],
        expectedType: TypeID?,
        implicitReceiverType: TypeID?,
        candidateArgumentTypes: [SymbolID: [Int: TypeID]],
        hasApplicableImplicitMembers: Bool,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        guard !hasApplicableImplicitMembers,
              let calleeName,
              let file = ctx.currentASTFile
        else {
            return candidates
        }

        let importedPaths = Set(file.imports.compactMap { importDecl -> [InternedString]? in
            guard !importDecl.isWildcard,
                  (importDecl.alias ?? importDecl.path.last) == calleeName
            else {
                return nil
            }
            return importDecl.path
        })
        guard !importedPaths.isEmpty else { return candidates }

        func isTopLevelNonExtensionFunction(_ candidate: SymbolID) -> Bool {
            guard let symbol = ctx.sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  !symbol.flags.contains(.localFunction),
                  let signature = ctx.sema.symbols.functionSignature(for: candidate)
            else {
                return false
            }
            if let parent = ctx.sema.symbols.parentSymbol(for: candidate),
               ctx.sema.symbols.symbol(parent)?.kind != .package
            {
                return false
            }
            return signature.receiverType == nil
        }

        let importedCandidates = candidates.filter { candidate in
            guard isTopLevelNonExtensionFunction(candidate),
                  let symbol = ctx.sema.symbols.symbol(candidate)
            else {
                return false
            }
            return importedPaths.contains(symbol.fqName)
        }
        let samePackageCandidates = candidates.filter { candidate in
            guard isTopLevelNonExtensionFunction(candidate),
                  let symbol = ctx.sema.symbols.symbol(candidate)
            else {
                return false
            }
            return Array(symbol.fqName.dropLast()) == file.packageFQName
        }
        guard !importedCandidates.isEmpty,
              !samePackageCandidates.isEmpty,
              Set(importedCandidates + samePackageCandidates) == Set(candidates)
        else {
            return candidates
        }

        // A lambda or callable reference can only satisfy a function-shaped
        // parameter, but its provisional argument type cannot prove that
        // during the probe. Keep only imported candidates whose mapped
        // parameters can accept the functional arguments; overload
        // resolution still performs the authoritative check afterwards.
        let hasFunctionalLiteralArgs = args.contains {
            ctx.ast.arena.expr($0.expr)?.isLambdaOrCallableRef == true
        }
        let probedImportedCandidates = hasFunctionalLiteralArgs
            ? importedCandidates.filter { candidate in
                functionalLiteralArgumentsFitParameters(
                    candidate, args: args, callRange: range, ctx: ctx
                )
            }
            : importedCandidates
        guard !probedImportedCandidates.isEmpty else { return candidates }

        let callArgs = zip(args, argTypes).map { argument, type in
            let literal = integerLiteralValues(argument.expr, ast: ctx.ast)
            return CallArg.source(
                argument,
                type: type,
                callRange: range,
                ast: ctx.ast,
                signedIntegerLiteral: literal.signed,
                unsignedIntegerLiteral: literal.unsigned
            )
        }
        let call = CallExpr(
            range: range,
            calleeName: calleeName,
            args: callArgs,
            explicitTypeArgs: explicitTypeArgs,
            dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type)
        )
        let probe = ctx.resolver.probeCall(
            candidates: probedImportedCandidates,
            call: call,
            expectedType: overloadResolutionExpectedType(from: expectedType, sema: ctx.sema),
            implicitReceiverType: implicitReceiverType,
            candidateArgumentTypes: candidateArgumentTypes,
            ctx: ctx.sema
        )
        guard !probe.viableCandidates.isEmpty else { return candidates }
        return probedImportedCandidates
    }

    /// Whether every lambda or callable-reference argument maps to a
    /// parameter that can accept a function value: a function type, an
    /// unresolved type parameter, or a SAM-convertible interface.
    private func functionalLiteralArgumentsFitParameters(
        _ candidate: SymbolID,
        args: [CallArgument],
        callRange: SourceRange,
        ctx: TypeInferenceContext
    ) -> Bool {
        let sema = ctx.sema
        guard let signature = sema.symbols.functionSignature(for: candidate),
              let mapping = parameterMappingForCallArguments(
                  args, in: signature, callRange: callRange, ctx: ctx
              )
        else {
            return false
        }
        for (index, argument) in args.enumerated() {
            guard ctx.ast.arena.expr(argument.expr)?.isLambdaOrCallableRef == true,
                  let parameterIndex = mapping[index]
            else {
                continue
            }
            let parameterType = signature.parameterTypes[parameterIndex]
            switch sema.types.kind(of: parameterType) {
            case .functionType, .typeParam:
                continue
            default:
                if driver.helpers.samFunctionType(for: parameterType, sema: sema) != nil {
                    continue
                }
                return false
            }
        }
        return true
    }
}

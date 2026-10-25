extension TypeCheckDriver {
    func registerInferredReturnFunctions(
        in declarationID: DeclID,
        context: TypeInferenceContext,
        visited: inout Set<DeclID>
    ) {
        guard visited.insert(declarationID).inserted,
              let declaration = ast.arena.decl(declarationID)
        else { return }

        switch declaration {
        case .funDecl:
            registerInferredReturnFunction(for: declarationID, context: context)

        case let .classDecl(classDecl):
            guard let symbol = sema.bindings.declSymbols[declarationID] else { return }
            var nestedObjects = classDecl.nestedObjects
            if let companionObject = classDecl.companionObject {
                nestedObjects.append(companionObject)
            }
            let (_, classContext, _) = declChecker.makeClassTypeCheckContext(
                classDecl: classDecl,
                symbol: symbol,
                nestedObjects: nestedObjects,
                ctx: context
            )
            for memberFunction in classDecl.memberFunctions {
                registerInferredReturnFunctions(in: memberFunction, context: classContext, visited: &visited)
            }
            for nestedDeclaration in classDecl.nestedClasses + nestedObjects {
                registerInferredReturnFunctions(
                    in: nestedDeclaration,
                    context: contextForNestedMember(nestedDeclaration, parent: classContext),
                    visited: &visited
                )
            }

        case let .interfaceDecl(interfaceDecl):
            guard let symbol = sema.bindings.declSymbols[declarationID] else { return }
            var nestedObjects = interfaceDecl.nestedObjects
            if let companionObject = interfaceDecl.companionObject {
                nestedObjects.append(companionObject)
            }
            let interfaceContext = declChecker.makeInterfaceTypeCheckContext(
                interfaceDecl: interfaceDecl,
                symbol: symbol,
                ctx: context
            )
            for memberFunction in interfaceDecl.memberFunctions {
                registerInferredReturnFunctions(in: memberFunction, context: interfaceContext, visited: &visited)
            }
            for nestedDeclaration in interfaceDecl.nestedClasses + nestedObjects {
                registerInferredReturnFunctions(
                    in: nestedDeclaration,
                    context: contextForNestedMember(nestedDeclaration, parent: interfaceContext),
                    visited: &visited
                )
            }

        case let .objectDecl(objectDecl):
            guard let symbol = sema.bindings.declSymbols[declarationID] else { return }
            let objectContext = declChecker.makeObjectTypeCheckContext(
                objectDecl: objectDecl,
                symbol: symbol,
                ctx: context
            )
            for memberFunction in objectDecl.memberFunctions {
                registerInferredReturnFunctions(in: memberFunction, context: objectContext, visited: &visited)
            }
            for nestedDeclaration in objectDecl.nestedClasses + objectDecl.nestedObjects {
                registerInferredReturnFunctions(
                    in: nestedDeclaration,
                    context: contextForNestedMember(nestedDeclaration, parent: objectContext),
                    visited: &visited
                )
            }

        case .propertyDecl, .typeAliasDecl, .enumEntryDecl:
            break
        }
    }

    private func contextForNestedMember(
        _ declarationID: DeclID,
        parent context: TypeInferenceContext
    ) -> TypeInferenceContext {
        switch ast.arena.decl(declarationID) {
        case let .classDecl(classDecl):
            return context.nestedClassContext(isInner: classDecl.isInner)
        case .interfaceDecl:
            return context.copying(outerReceiverTypes: [])
        default:
            return context
        }
    }

    func registerInferredReturnFunction(
        for declarationID: DeclID,
        context: TypeInferenceContext
    ) {
        guard case let .funDecl(function)? = ast.arena.decl(declarationID),
              function.returnType == nil,
              case .expr = function.body,
              let symbol = sema.bindings.declSymbols[declarationID]
        else { return }
        inferredReturnFunctions[symbol] = (
            function,
            context.with(currentDeclSymbol: symbol)
        )
    }

    /// Infer a source function in its declaration's scope before overload
    /// resolution consumes its return type. In particular, a later extension
    /// such as `fun Parser<Char>.string() = map { it.toString() }` must not
    /// contribute the header's `Any` placeholder to an enclosing vararg call.
    func inferFunctionReturnTypesIfNeeded(for candidates: [SymbolID]) {
        for symbol in candidates {
            guard let declaration = inferredReturnFunctions[symbol],
                  !checkedInferredReturnFunctions.contains(symbol),
                  !checkingInferredReturnFunctions.contains(symbol)
            else { continue }
            // Use the declaration's file scope and receiver/parameter bindings,
            // never the caller's lambda locals or expected return type.
            let checkpoint = diagnostics.checkpoint()
            let signature = sema.symbols.functionSignature(for: symbol)
            declChecker.typeCheckFunctionDecl(
                declaration.function,
                symbol: symbol,
                ctx: declaration.context,
                solver: solver,
                diagnostics: diagnostics
            )
            let errors = diagnostics.diagnostics.dropFirst(checkpoint).filter { $0.severity == .error }
            if !errors.isEmpty,
               !errors.contains(where: { $0.message.hasPrefix("Recursive ") })
            {
                // An untyped member dependency may become concrete during its
                // owner's normal pass. Retry this declaration authoritatively;
                // do not turn a speculative placeholder failure into a new error.
                diagnostics.rollback(to: checkpoint)
                if let signature { sema.symbols.setFunctionSignature(signature, for: symbol) }
                checkedInferredReturnFunctions.remove(symbol)
                deferredInferredReturnFunctions.insert(symbol)
            }
        }
    }

    func diagnoseRecursiveInferredReturnType(for symbol: SymbolID) {
        guard checkingInferredReturnFunctions.contains(symbol),
              let declaration = inferredReturnFunctions[symbol]
        else { return }
        // Every active dependent must remain retryable even when the same
        // recursive diagnostic was already emitted and will be deduplicated.
        // A speculative caller can still roll that diagnostic back later.
        deferredInferredReturnFunctions.formUnion(checkingInferredReturnFunctions)
        deferredInferredProperties.formUnion(checkingInferredProperties)
        guard !diagnostics.diagnostics.contains(where: {
            $0.code == "KSWIFTK-SEMA-INFER" && $0.primaryRange == declaration.function.range
        }) else { return }
        diagnostics.error(
            "KSWIFTK-SEMA-INFER",
            "Recursive return type inference requires an explicit return type.",
            range: declaration.function.range
        )
    }
}

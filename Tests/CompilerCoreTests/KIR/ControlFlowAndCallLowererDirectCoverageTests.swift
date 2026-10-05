#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ControlFlowAndCallLowererDirectCoverageTests {
    @Test(arguments: [false, true], [false, true])
    func resultCallbackAdapterKeepsErasedReturn(
        hasCallableInfo: Bool, hasClosureParam: Bool
    ) throws {
        let fixture = makeKIRDirectLoweringFixture()
        let functionType = fixture.types.make(.functionType(FunctionType(
            params: [], returnType: fixture.types.booleanType,
            isSuspend: false, nullability: .nonNull
        )))
        let source = appendTypedExpr(
            .nameRef(fixture.interner.intern("block"), makeRange()),
            type: functionType, fixture: fixture
        )
        let callable = fixture.kirArena.appendTemporary(type: functionType)
        let closure = fixture.kirArena.appendTemporary(type: fixture.types.intType)
        let symbol = defineSemanticSymbol(in: fixture, kind: .function, fqName: ["pkg", "block"])
        if hasCallableInfo {
            fixture.driver.ctx.registerCallableValue(
                callable, symbol: symbol, callee: fixture.interner.intern("block"),
                captureArguments: [closure], hasClosureParam: hasClosureParam
            )
        }
        var instructions: [KIRInstruction] = []
        let arguments = fixture.driver.callLowerer.makeClosureThunkExpandedArguments(
            loweredArgID: callable, argExprID: source, returnsErasedValue: true,
            sema: fixture.sema, arena: fixture.kirArena, interner: fixture.interner,
            instructions: &instructions
        )
        #expect(arguments.count == 2)
        guard case let .symbolRef(adapterSymbol)? = fixture.kirArena.expr(arguments[0]) else {
            Issue.record("Expected callback adapter function pointer")
            return
        }
        let adapter = try #require(fixture.kirArena.function(for: adapterSymbol))
        #expect(adapter.returnType == fixture.types.anyType)
        #expect(adapter.params.count == 1)
        #expect(arguments[1] == (hasCallableInfo ? closure : callable))
        #expect(adapter.body.contains {
            guard case .returnValue = $0 else { return false }
            return true
        })
        let call = try #require(adapter.body.compactMap { instruction -> InternedString? in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return nil }
            return callee
        }.first)
        #expect(fixture.interner.resolve(call) == (hasCallableInfo ? "block" : "kk_function_invoke_0"))
        if !hasCallableInfo {
            #expect(adapter.body.contains {
                guard case .rethrow = $0 else { return false }
                return true
            })
        }
    }

    @Test func testControlFlowLowererCatchBindingAndLegacyTypeResolution() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()

        let catchExprID = fixture.astArena.appendExpr(.intLiteral(0, range))
        let catchClause = CatchClause(
            paramName: fixture.interner.intern("e"),
            paramType: fixture.astArena.appendTypeRef(.named(path: [fixture.interner.intern("Int")], args: [], nullable: false)),
            body: catchExprID,
            range: range
        )

        let boundSymbol = defineSemanticSymbol(in: fixture, kind: .valueParameter, fqName: ["pkg", "e"])
        let boundType = fixture.types.make(.primitive(.int, .nonNull))
        fixture.bindings.bindCatchClause(
            catchExprID,
            binding: CatchClauseBinding(parameterSymbol: boundSymbol, parameterType: boundType)
        )

        let resolvedExisting = fixture.driver.controlFlowLowerer.resolveCatchClauseBinding(
            catchClause,
            ast: fixture.ast,
            sema: fixture.sema,
            interner: fixture.interner
        )
        #expect(resolvedExisting.parameterSymbol == boundSymbol)
        #expect(resolvedExisting.parameterType == boundType)

        let fallbackExprID = fixture.astArena.appendExpr(.intLiteral(1, range))
        let fallbackClause = CatchClause(
            paramName: fixture.interner.intern("x"),
            paramType: fixture.astArena.appendTypeRef(.named(path: [fixture.interner.intern("Long")], args: [], nullable: false)),
            body: fallbackExprID,
            range: range
        )
        let fallbackSymbol = defineSemanticSymbol(in: fixture, kind: .valueParameter, fqName: ["pkg", "x"])
        fixture.bindings.bindIdentifier(fallbackExprID, symbol: fallbackSymbol)

        let resolvedFallback = fixture.driver.controlFlowLowerer.resolveCatchClauseBinding(
            fallbackClause,
            ast: fixture.ast,
            sema: fixture.sema,
            interner: fixture.interner
        )
        #expect(resolvedFallback.parameterSymbol == fallbackSymbol)
        #expect(fixture.types.kind(of: resolvedFallback.parameterType) == .primitive(.long, .nonNull))

        func namedRef(_ path: [String]) -> TypeRefID {
            fixture.astArena.appendTypeRef(
                .named(path: path.map { fixture.interner.intern($0) }, args: [], nullable: false)
            )
        }

        #expect(
            fixture.driver.controlFlowLowerer.resolveLegacyCatchClauseType(
                nil,
                ast: fixture.ast,
                sema: fixture.sema,
                interner: fixture.interner
            ) == fixture.types.anyType
        )

        let builtinNames = [
            ("Int", TypeKind.primitive(.int, .nonNull)),
            ("Float", TypeKind.primitive(.float, .nonNull)),
            ("Double", TypeKind.primitive(.double, .nonNull)),
            ("Boolean", TypeKind.primitive(.boolean, .nonNull)),
            ("Char", TypeKind.primitive(.char, .nonNull)),
            ("String", TypeKind.stringStruct(.nonNull)),
        ]

        for (name, expectedKind) in builtinNames {
            let resolved = fixture.driver.controlFlowLowerer.resolveLegacyCatchClauseType(
                namedRef([name]),
                ast: fixture.ast,
                sema: fixture.sema,
                interner: fixture.interner
            )
            #expect(fixture.types.kind(of: resolved) == expectedKind)
        }

        let classSymbol = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["CustomThrowable"])
        let resolvedClass = fixture.driver.controlFlowLowerer.resolveLegacyCatchClauseType(
            namedRef(["CustomThrowable"]),
            ast: fixture.ast,
            sema: fixture.sema,
            interner: fixture.interner
        )
        #expect(
            fixture.types.kind(of: resolvedClass) ==
            .classType(ClassType(classSymbol: classSymbol, args: [], nullability: .nonNull))
        )

        let qualifiedClassSymbol = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["pkg", "QualifiedThrowable"])
        let resolvedQualified = fixture.driver.controlFlowLowerer.resolveLegacyCatchClauseType(
            namedRef(["pkg", "QualifiedThrowable"]),
            ast: fixture.ast,
            sema: fixture.sema,
            interner: fixture.interner
        )
        #expect(
            fixture.types.kind(of: resolvedQualified) ==
            .classType(ClassType(classSymbol: qualifiedClassSymbol, args: [], nullability: .nonNull))
        )

        let unresolvedType = fixture.driver.controlFlowLowerer.resolveLegacyCatchClauseType(
            namedRef(["MissingType"]),
            ast: fixture.ast,
            sema: fixture.sema,
            interner: fixture.interner
        )
        #expect(unresolvedType == fixture.types.errorType)

        #expect(fixture.driver.controlFlowLowerer.isCatchAllType(fixture.types.anyType, sema: fixture.sema))
        #expect(
            fixture.driver.controlFlowLowerer.isCatchAllType(fixture.types.nullableAnyType, sema: fixture.sema)
        )
        #expect(fixture.driver.controlFlowLowerer.isCatchAllType(fixture.types.errorType, sema: fixture.sema))
        #expect(!(fixture.driver.controlFlowLowerer.isCatchAllType(fixture.types.intType, sema: fixture.sema)))
    }

    /// `catch (e: Exception)` must keep its runtime type check: an `Error`
    /// (e.g. `TODO()`'s NotImplementedError) is a Throwable but not an
    /// Exception, so only `Throwable` may skip the check as a catch-all.
    @Test func testOnlyThrowableIsCatchAllClassType() {
        let fixture = makeKIRDirectLoweringFixture()
        func classType(_ name: String) -> TypeID {
            let symbol = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["kotlin", name])
            return fixture.types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
        }
        let lowerer = fixture.driver.controlFlowLowerer
        let throwableType = classType("Throwable")
        let exceptionType = classType("Exception")
        let errorType = classType("Error")

        #expect(lowerer.isCatchAllType(throwableType, sema: fixture.sema, interner: fixture.interner))
        #expect(!lowerer.isCatchAllType(exceptionType, sema: fixture.sema, interner: fixture.interner))
        #expect(!lowerer.isCatchAllType(errorType, sema: fixture.sema, interner: fixture.interner))
    }

    @Test func testControlFlowLowererForwardersEmitInstructions() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()

        let boolType = fixture.types.make(.primitive(.boolean, .nonNull))
        let intType = fixture.types.make(.primitive(.int, .nonNull))

        let iterableExpr = fixture.astArena.appendExpr(.intLiteral(10, range))
        fixture.bindings.bindExprType(iterableExpr, type: intType)
        let bodyExpr = fixture.astArena.appendExpr(.intLiteral(1, range))
        fixture.bindings.bindExprType(bodyExpr, type: intType)

        let forExprID = fixture.astArena.appendExpr(
            .forDestructuringExpr(
                names: [fixture.interner.intern("item")],
                iterable: iterableExpr,
                body: bodyExpr,
                range: range
            )
        )
        let componentSymbol = defineSemanticSymbol(
            in: fixture,
            kind: .local,
            fqName: ["__for_destructuring_\(forExprID.rawValue)", "item"]
        )
        fixture.symbols.setPropertyType(intType, for: componentSymbol)

        let conditionA = fixture.astArena.appendExpr(.boolLiteral(true, range))
        fixture.bindings.bindExprType(conditionA, type: boolType)
        let conditionB = fixture.astArena.appendExpr(.boolLiteral(false, range))
        fixture.bindings.bindExprType(conditionB, type: boolType)

        let whenExprID = fixture.astArena.appendExpr(
            .whenExpr(
                subject: nil,
                branches: [WhenBranch(conditions: [conditionA, conditionB], body: bodyExpr, range: range)],
                elseExpr: bodyExpr,
                range: range
            )
        )
        fixture.bindings.bindExprType(whenExprID, type: intType)

        var lowered = KIRLoweringEmitContext([
            .call(
                symbol: nil,
                callee: fixture.interner.intern("mayThrow"),
                arguments: [],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ),
        ])
        let exceptionSlot = fixture.kirArena.appendExpr(.temporary(3), type: fixture.types.anyType)
        let exceptionTypeSlot = fixture.kirArena.appendExpr(.temporary(4), type: intType)
        var emitted = KIRLoweringEmitContext()

        fixture.driver.controlFlowLowerer.appendThrowAwareInstructions(
            lowered,
            exceptionSlot: exceptionSlot,
            exceptionTypeSlot: exceptionTypeSlot,
            thrownTarget: 999,
            sema: fixture.sema,
            interner: fixture.interner,
            arena: fixture.kirArena,
            emit: &emitted
        )
        #expect(emitted.instructions.contains { instruction in
            guard case .jumpIfNotNull = instruction else { return false }
            return true
        })

        let shared = fixture.makeShared()
        _ = fixture.driver.controlFlowLowerer.lowerForDestructuringExpr(
            forExprID,
            names: [fixture.interner.intern("item")],
            iterableExpr: iterableExpr,
            bodyExpr: bodyExpr,
            shared: shared,
            emit: &emitted
        )

        _ = fixture.driver.controlFlowLowerer.lowerWhenExpr(
            whenExprID,
            subject: nil,
            branches: [WhenBranch(conditions: [conditionA, conditionB], body: bodyExpr, range: range)],
            elseExpr: bodyExpr,
            shared: shared,
            emit: &emitted
        )

        #expect(emitted.instructions.contains { instruction in
            if case .label = instruction { return true }
            return false
        })
        #expect(emitted.instructions.contains { instruction in
            if case .call = instruction { return true }
            return false
        })

        // Keep compiler warnings away for mutable local that needs to be var.
        lowered.instructions.append(.nop)
    }

    @Test func testCallLowererLowersClassNameMemberValuesAsDirectSymbolRefs() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()

        let colorSym = defineSemanticSymbol(in: fixture, kind: .enumClass, fqName: ["Color"])
        let colorType = fixture.types.make(
            .classType(ClassType(classSymbol: colorSym, args: [], nullability: .nonNull))
        )
        let redSym = defineSemanticSymbol(in: fixture, kind: .field, fqName: ["Color", "Red"])
        fixture.symbols.setPropertyType(colorType, for: redSym)

        let colorRef = fixture.astArena.appendExpr(.nameRef(fixture.interner.intern("Color"), range))
        fixture.bindings.bindIdentifier(colorRef, symbol: colorSym)
        fixture.bindings.bindExprType(colorRef, type: colorType)

        let redAccess = fixture.astArena.appendExpr(.memberCall(
            receiver: colorRef,
            callee: fixture.interner.intern("Red"),
            typeArgs: [],
            args: [],
            range: range
        ))
        fixture.bindings.bindIdentifier(redAccess, symbol: redSym)
        fixture.bindings.bindExprType(redAccess, type: colorType)

        var enumInstructions: [KIRInstruction] = []
        _ = fixture.driver.lowerExpr(
            redAccess,
            ast: fixture.ast,
            sema: fixture.sema,
            arena: fixture.kirArena,
            interner: fixture.interner,
            propertyConstantInitializers: [:],
            instructions: &enumInstructions
        )
        #expect(enumInstructions.contains { instruction in
            if case let .constValue(_, .symbolRef(symbol)) = instruction {
                return symbol == redSym
            }
            return false
        })
        #expect(!(enumInstructions.contains { instruction in
            if case .call = instruction {
                return true
            }
            return false
        }))

        let exprSym = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["Expr"])
        let exprType = fixture.types.make(
            .classType(ClassType(classSymbol: exprSym, args: [], nullability: .nonNull))
        )
        let nestedObjectSym = defineSemanticSymbol(in: fixture, kind: .object, fqName: ["Expr", "A"])
        fixture.symbols.setParentSymbol(exprSym, for: nestedObjectSym)
        let nestedObjectType = fixture.types.make(
            .classType(ClassType(classSymbol: nestedObjectSym, args: [], nullability: .nonNull))
        )

        let exprRef = fixture.astArena.appendExpr(.nameRef(fixture.interner.intern("Expr"), range))
        fixture.bindings.bindIdentifier(exprRef, symbol: exprSym)
        fixture.bindings.bindExprType(exprRef, type: exprType)

        let objectAccess = fixture.astArena.appendExpr(.memberCall(
            receiver: exprRef,
            callee: fixture.interner.intern("A"),
            typeArgs: [],
            args: [],
            range: range
        ))
        fixture.bindings.bindIdentifier(objectAccess, symbol: nestedObjectSym)
        fixture.bindings.bindExprType(objectAccess, type: nestedObjectType)

        var objectInstructions: [KIRInstruction] = []
        _ = fixture.driver.lowerExpr(
            objectAccess,
            ast: fixture.ast,
            sema: fixture.sema,
            arena: fixture.kirArena,
            interner: fixture.interner,
            propertyConstantInitializers: [:],
            instructions: &objectInstructions
        )
        #expect(objectInstructions.contains { instruction in
            if case let .constValue(_, .symbolRef(symbol)) = instruction {
                return symbol == nestedObjectSym
            }
            return false
        })
        #expect(!(objectInstructions.contains { instruction in
            if case .call = instruction {
                return true
            }
            return false
        }))
    }
}
#endif

#if canImport(Testing)
    @testable import CompilerCore
    import Testing

    struct CrossFilePropertyInferenceTests {
        @Test
        func inferredBooleanPropertiesResolveInEitherFileOrder() throws {
            let use = """
            package sample
            fun readInferredTopLevel(): Boolean = inferredTopLevel
            fun readExplicitTopLevel(): Boolean = explicitTopLevel
            fun readInferredMember(holder: Holder): Boolean = holder.inferredMember
            fun readExplicitMember(holder: Holder): Boolean = holder.explicitMember
            fun readLazy(descriptor: Descriptor<String>): Boolean = descriptor.defaultValueSet
            fun readExplicitReturn(holder: Holder): Boolean = holder.explicitReturn()
            fun readInferredReturnWithoutConstraint(holder: Holder) = holder.inferredReturn()
            """
            let declarations = """
            package sample
            val inferredTopLevel = true
            val explicitTopLevel: Boolean = true
            class Holder {
                val inferredMember = true
                val explicitMember: Boolean = true
                fun inferredReturn() = true
                fun explicitReturn(): Boolean = true
            }
            class Descriptor<T>(val defaultValue: T?) {
                val defaultValueSet by lazy { defaultValue != null }
            }
            """

            for sources in [[use, declarations], [declarations, use]] {
                let (sema, interner) = try SemaFixture(
                    surface: "inferred Boolean properties across files"
                ).make(sources: sources)

                try expectPropertyType(
                    ["sample", "inferredTopLevel"],
                    equals: sema.types.booleanType,
                    in: sema,
                    interner: interner
                )
                try expectPropertyType(
                    ["sample", "explicitTopLevel"],
                    equals: sema.types.booleanType,
                    in: sema,
                    interner: interner
                )
                try expectPropertyType(
                    ["sample", "Holder", "inferredMember"],
                    equals: sema.types.booleanType,
                    in: sema,
                    interner: interner
                )
                try expectPropertyType(
                    ["sample", "Holder", "explicitMember"],
                    equals: sema.types.booleanType,
                    in: sema,
                    interner: interner
                )
                try expectPropertyType(
                    ["sample", "Descriptor", "defaultValueSet"],
                    equals: sema.types.booleanType,
                    in: sema,
                    interner: interner
                )
                for functionName in ["inferredReturn", "explicitReturn"] {
                    let function = try #require(sema.symbols.lookup(
                        fqName: ["sample", "Holder", functionName].map(interner.intern)
                    ))
                    #expect(
                        sema.symbols.functionSignature(for: function)?.returnType == sema.types.booleanType
                    )
                }
            }
        }

        @Test
        func inferredIntegerStringAndDependentPropertiesResolveInEitherFileOrder() throws {
            let use = """
            package sample
            fun readTopLevelInt(): Int = dependentInt
            fun readTopLevelString(): String = dependentString
            fun readMemberInt(holder: Holder): Int = holder.dependentMemberInt
            fun readMemberString(holder: Holder): String = holder.dependentMemberString
            fun readLazyInt(holder: Holder): Int = holder.lazyMemberInt
            fun readLazyString(holder: Holder): String = holder.lazyMemberString
            """
            let declarations = """
            package sample
            val dependentInt = forwardInt + 2
            val forwardInt = 40
            val dependentString = forwardString + "!"
            val forwardString = "forward"
            class Holder {
                val dependentMemberInt = forwardMemberInt + 2
                val forwardMemberInt = 40
                val dependentMemberString = forwardMemberString + "!"
                val forwardMemberString = "member"
                val lazyMemberInt by lazy { forwardMemberInt + 2 }
                val lazyMemberString by lazy { forwardMemberString + "!" }
            }
            """

            for sources in [[use, declarations], [declarations, use]] {
                let (sema, interner) = try SemaFixture(
                    surface: "inferred Int and String properties across files"
                ).make(sources: sources)

                for propertyName in ["forwardInt", "dependentInt"] {
                    try expectPropertyType(
                        ["sample", propertyName],
                        equals: sema.types.intType,
                        in: sema,
                        interner: interner
                    )
                }
                for propertyName in ["forwardString", "dependentString"] {
                    try expectPropertyType(
                        ["sample", propertyName],
                        equals: sema.types.stringType,
                        in: sema,
                        interner: interner
                    )
                }
                for propertyName in ["forwardMemberInt", "dependentMemberInt", "lazyMemberInt"] {
                    try expectPropertyType(
                        ["sample", "Holder", propertyName],
                        equals: sema.types.intType,
                        in: sema,
                        interner: interner
                    )
                }
                for propertyName in ["forwardMemberString", "dependentMemberString", "lazyMemberString"] {
                    try expectPropertyType(
                        ["sample", "Holder", propertyName],
                        equals: sema.types.stringType,
                        in: sema,
                        interner: interner
                    )
                }
            }
        }

        @Test
        func inferredPropertyCyclesKeepTheirTypeDiagnosticInEitherFileOrder() throws {
            let use = """
            package sample
            fun readCycle(): Int = cycleA
            """
            let declarations = """
            package sample
            val cycleA = cycleB
            val cycleB = cycleA
            """

            for sources in [[use, declarations], [declarations, use]] {
                try withTemporaryFiles(contents: sources) { paths in
                    let ctx = makeCompilationContext(inputs: paths)
                    try runSema(ctx)
                    #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" })
                }
            }
        }

        @Test
        func directConstructorPropertyStillPrechecksAgainstItsHeader() throws {
            let use = """
            package sample
            fun readToken(): Token = directToken
            """
            let declarations = """
            package sample
            val directToken = Token()
            class Token
            """

            for sources in [[use, declarations], [declarations, use]] {
                let (sema, interner) = try SemaFixture(
                    surface: "direct constructor property pre-inference"
                ).make(sources: sources)
                let tokenSymbol = try #require(sema.symbols.lookup(
                    fqName: ["sample", "Token"].map(interner.intern)
                ))
                let tokenType = sema.types.make(.classType(ClassType(
                    classSymbol: tokenSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                try expectPropertyType(
                    ["sample", "directToken"],
                    equals: tokenType,
                    in: sema,
                    interner: interner
                )
            }
        }

        @Test
        func functionInitializedPropertyKeepsDeclarationOrder() throws {
            let source = """
            package sample
            fun newToken() = Token()
            val functionInitializedToken = newToken()
            fun readToken(): Token = functionInitializedToken
            class Token
            """
            let (sema, interner) = try SemaFixture(
                surface: "function-initialized property order"
            ).make(source: source)
            let tokenSymbol = try #require(sema.symbols.lookup(
                fqName: ["sample", "Token"].map(interner.intern)
            ))
            let tokenType = sema.types.make(.classType(ClassType(
                classSymbol: tokenSymbol,
                args: [],
                nullability: .nonNull
            )))

            try expectPropertyType(
                ["sample", "functionInitializedToken"],
                equals: tokenType,
                in: sema,
                interner: interner
            )
            let functionSymbol = try #require(sema.symbols.lookup(
                fqName: ["sample", "newToken"].map(interner.intern)
            ))
            #expect(sema.symbols.functionSignature(for: functionSymbol)?.returnType == tokenType)
        }

        private func expectPropertyType(
            _ fqName: [String],
            equals expectedType: TypeID,
            in sema: SemaModule,
            interner: StringInterner
        ) throws {
            let property = try #require(sema.symbols.lookup(
                fqName: fqName.map(interner.intern)
            ))
            #expect(sema.symbols.propertyType(for: property) == expectedType)
        }
    }
#endif

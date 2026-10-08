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

import Foundation

final class JVMProgramBuilder {
    let context: CompilationContext
    let ast: ASTModule
    let sema: SemaModule
    var classes: [SymbolID: JVMClassPlan] = [:]
    var methods: [SymbolID: JVMForeignMethod] = [:]
    var collectionInterfaceMethods: [SymbolID: JVMForeignMethod] = [:]
    var properties: [SymbolID: JVMProperty] = [:]
    var facadeName = ""
    var facadePlan: JVMClassPlan?
    var references: [SymbolID: JVMFunctionReference] = [:]
    var localFunctions: [SymbolID: JVMLocalFunctionPlan] = [:]
    var syntheticFunctions: [String: [JVMFunction]] = [:]
    var closureClasses: [JVMClass] = []
    var functionArities: Set<Int> = []
    var nextClosure = 0
    var needsSuspendCoroutine = false
    var coroutineIntrinsicOwner = ""
    var extensionSymbols: Set<SymbolID> = []
    var inlineDeclarations: [SymbolID: FunDecl] = [:]
    var sourceParameters: [SymbolID: [ValueParamDecl]] = [:]
    var sourceDeclarations: [SymbolID: FunDecl] = [:]
    var sourceRangeResultSymbols: Set<SymbolID> = []
    var inlineTypeArguments: [SymbolID: TypeID] = [:]
    var textLibraryMethods: [SymbolID: JVMTextLibraryMethod] = [:]
    var textLibraryProperties: [SymbolID: JVMForeignMethod] = [:]
    var textLibraryFields: [SymbolID: JVMField] = [:]
    let platformOperations: [String: JVMPlatformOperation]
    var rawAnnotationConstructions: [String: ExprID] = [:]

    init(context: CompilationContext) throws {
        guard let ast = context.ast, let sema = context.sema else {
            throw JVMFrontendError(message: "JVM semantic analysis is unavailable.")
        }
        self.context = context; self.ast = ast; self.sema = sema
        self.platformOperations = context.options.stdlibOnly ? try JVMStdlibCatalog.platformOperations() : [:]
    }

    func type(_ id: TypeID) throws -> JVMValueType {
        let actual = specialized(id)
        noteFunctionTypes(actual)
        return try JVMClasspathIndex.type(actual, sema: sema, ctx: context)
    }
    func hasSourceRangeOperator(_ id: ExprID) -> Bool {
        if let symbol = sema.bindings.callBinding(for: id)?.chosenCallee,
           methods[symbol] != nil || references[symbol] != nil || inlineDeclarations[symbol] != nil {
            return true
        }
        return sema.bindings.identifierSymbol(for: id).map(sourceRangeResultSymbols.contains) ?? false
    }
    /// The declared type without the active inline substitution. Storage that
    /// outlives one instantiation (anonymous object capture fields, shared
    /// mutable-variable cells) is emitted once, so it must erase reified type
    /// parameters to their bounds rather than adopt a call site's argument.
    func erasedType(_ id: TypeID) throws -> JVMValueType {
        noteFunctionTypes(id)
        return try JVMClasspathIndex.type(id, sema: sema, ctx: context)
    }
    func expressionType(_ id: ExprID) throws -> JVMValueType {
        guard let type = sema.bindings.exprType(for: id) else {
            throw JVMFrontendError(message: "JVM expression has no resolved type.", range: ast.arena.exprRange(id))
        }
        let mapped = try self.type(type)
        // Primitive range expressions carry their scalar element type in exprTypes,
        // but the JVM materializes a nominal range object. A source-backed rangeTo
        // may return another declared type, so preserve its resolved result type.
        if sema.bindings.isRangeExpr(id), !hasSourceRangeOperator(id) {
            if sema.bindings.isCharRangeExpr(id) {
                return .reference("kotlin/ranges/CharRange", nullable: false)
            }
            if mapped == .long {
                return .reference("kotlin/ranges/LongRange", nullable: false)
            }
            if mapped == .int {
                return .reference("kotlin/ranges/IntRange", nullable: false)
            }
        }
        return mapped
    }
    static func isIdentifier(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        func start(_ b: UInt8) -> Bool { (65...90).contains(b) || (97...122).contains(b) || b == 95 }
        guard let first = bytes.first, start(first) else { return false }
        return bytes.dropFirst().allSatisfy { start($0) || (48...57).contains($0) }
    }

    static func fileIdentity(for file: ASTFile, context: CompilationContext) throws -> (String, String) {
        guard file.scriptBody.isEmpty else {
            throw JVMFrontendError(message: "JVM source files cannot contain scripts.")
        }
        let filename = URL(fileURLWithPath: context.sourceManager.path(of: file.fileID)).lastPathComponent
        let stem = (filename as NSString).deletingPathExtension
        let package = file.packageFQName.map(context.interner.resolve)
        guard isIdentifier(stem), package.allSatisfy(isIdentifier) else {
            throw JVMFrontendError(message: "JVM M6 requires ASCII identifiers for the source filename and package.")
        }
        var facade = String(stem.prefix(1)).uppercased() + stem.dropFirst() + "Kt"
        guard file.annotations.count <= 1 else {
            throw JVMFrontendError(message: "JVM supports one fully qualified @file:kotlin.jvm.JvmName annotation.")
        }
        if let annotation = file.annotations.first {
            guard annotation.useSiteTarget == "file", annotation.name == "kotlin.jvm.JvmName", annotation.arguments.count == 1,
                  let raw = annotation.arguments.first?.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let data = ("[" + raw + "]").data(using: .utf8), let names = try? JSONSerialization.jsonObject(with: data) as? [String],
                  names.count == 1, isIdentifier(names[0]) else {
                throw JVMFrontendError(message: "JVM @file:kotlin.jvm.JvmName requires one constant ASCII identifier.")
            }
            facade = names[0]
        }
        return ((package + [facade]).joined(separator: "/"), filename)
    }

    func build() throws -> JVMProgram {
        let files = ast.files.filter { context.sourceManager.origin(of: $0.fileID) == .user }
        guard !files.isEmpty else { throw JVMFrontendError(message: "JVM compilation requires source files.") }
        let names = try files.map { try Self.fileIdentity(for: $0, context: context) }
        if Set(names.map { $0.0 }).count != names.count {
            guard context.options.stdlibOnly else { throw JVMFrontendError(message: "Duplicate JVM file facade name.") }
            let repeated = Dictionary(grouping: names.indices, by: { names[$0].0 }).values.filter { $0.count > 1 }.flatMap { $0 }
            guard repeated.allSatisfy({ index in !files[index].topLevelDecls.contains { if case .propertyDecl = ast.arena.decl($0) { return true }; return false } }) else {
                throw JVMFrontendError(message: "A shared stdlib facade cannot contain top-level properties.")
            }
        }
        facadeName = names[0].0
        coroutineIntrinsicOwner = facadeName
        try prepareTextLibrary()
        try prepareDelegateInterfaces()
        try prepareLazyProperty()
        try prepareCollectionInterfaces()
        try prepareClasses(files.flatMap(\.topLevelDecls))
        try prepareClassDelegates()
        try prepareCollectionDelegationMarkers()
        var plans: [JVMClassPlan?] = []
        var declarationsByFile: [[(FunDecl, JVMFunctionReference)]] = []
        for (index, file) in files.enumerated() {
            facadeName = names[index].0; facadePlan = nil
            let propertyIDs = file.topLevelDecls.filter { if case .propertyDecl = ast.arena.decl($0) { return true }; return false }
            if let first = propertyIDs.first, case let .propertyDecl(property) = ast.arena.decl(first) {
                let c = ClassDecl(range: property.range, name: context.interner.intern(facadeName), modifiers: [], classBodyInitOrder: propertyIDs.indices.map { .property($0) }, memberProperties: propertyIDs)
                let plan = JVMClassPlan(symbol: SymbolID(rawValue: -90000000 - Int32(index)), name: facadeName, declaration: c)
                plan.isFacade = true; facadePlan = plan
                try prepareProperties(plan, ids: propertyIDs)
            }
            guard !classes.values.contains(where: { $0.name == facadeName }) else { throw JVMFrontendError(message: "JVM facade name clashes with a class.") }
            var declarations: [(FunDecl, JVMFunctionReference)] = []
            var signatures: Set<String> = []
            for id in file.topLevelDecls {
                guard case let .funDecl(f) = ast.arena.decl(id) else { continue }
                guard let symbol = sema.bindings.declSymbol(for: id) else { throw JVMFrontendError(message: "Missing JVM function binding.") }
                let ref = try functionReference(f, symbol: symbol, member: false)
                guard signatures.insert(ref.name + ref.descriptor).inserted else { throw JVMFrontendError(message: "Duplicate JVM method signature.", range: f.range) }
                var owned = ref; owned.owner = facadeName
                references[symbol] = owned; declarations.append((f, owned))
            }
            plans.append(facadePlan); declarationsByFile.append(declarations)
        }
        var facades: [JVMProgram] = []
        for (index, file) in files.enumerated() {
            facadeName = names[index].0; facadePlan = plans[index]
            let declarations = declarationsByFile[index]
            let mains = declarations.filter { $0.1.name == "main" }
            let hasMain = mains.contains { $0.0.typeParams.isEmpty && $0.1.parameters.isEmpty && $0.1.result == .unit }
            guard mains.isEmpty || hasMain else {
                throw JVMFrontendError(message: "JVM entry point must be fun main(): Unit with no arguments.")
            }
            guard Self.isIdentifier(context.options.moduleName) else { throw JVMFrontendError(message: "JVM module name requires an ASCII identifier.") }
            let functions = try declarations.map { declaration, reference in
                let symbol = file.topLevelDecls.compactMap { id -> SymbolID? in
                    if case let .funDecl(f) = ast.arena.decl(id), f.range == declaration.range { return sema.bindings.declSymbol(for: id) }; return nil
                }.first!
                let builder = JVMFunctionBuilder(program: self, declaration: declaration, reference: reference)
                builder.functionSymbol = symbol
                builder.semanticSignature = sema.symbols.functionSignature(for: symbol)
                return try annotated(describe(builder.build(), signature: builder.semanticSignature!, parameters: declaration.typeParams), symbol: symbol)
            }
            var defaults: [JVMFunction] = []
            for id in file.topLevelDecls {
                if case let .funDecl(f) = ast.arena.decl(id), f.valueParams.contains(where: \.hasDefaultValue), let symbol = sema.bindings.declSymbol(for: id) { defaults.append(try defaultFunction(symbol: symbol, declaration: f, plan: nil)) }
            }
            var facadeFunctions: [JVMFunction] = []
            if let plan = facadePlan {
                for (_, declaration, property) in plan.properties { facadeFunctions += try emitAccessors(plan, declaration, property) }
                let b = try nominalBuilder(plan, name: "<clinit>", staticBody: true)
                for (symbol, field) in plan.propertyTokens.sorted(by: { $0.value.name < $1.value.name }) {
                    let property = properties[symbol]!
                    b.instructions.append(.putStatic(field, try b.convert(b.propertyToken(name: property.name, owner: plan.name, signature: property.getter.name + property.getter.descriptor, topLevel: true, mutable: property.setter != nil), to: field.type)))
                }
                let placeholder = try b.constant(.null, .reference("java/lang/Object", nullable: true))
                try emitInitializers(plan, builder: b, object: placeholder)
                if !b.terminated { b.instructions.append(.returnValue(nil)) }
                var initializer = b.finish(); initializer.access = 8; facadeFunctions.append(initializer)
            }
            var output = JVMProgram(internalClassName: facadeName, sourceFileName: names[index].1, functions: functions + defaults + facadeFunctions, hasMain: hasMain, moduleName: context.options.moduleName)
            output.properties = facadePlan?.properties.map { $0.2 } ?? []
            output.extraFields = (facadePlan?.properties.compactMap { $0.2.delegateField } ?? []) + (facadePlan.map { Array($0.propertyTokens.values).sorted { $0.name < $1.name } } ?? [])
            output.typeAliases = try aliases(file.topLevelDecls.compactMap { if case let .typeAliasDecl(alias) = ast.arena.decl($0) { return alias }; return nil }, package: file.packageFQName)
            facades.append(output)
        }
        if context.options.stdlibOnly {
            var merged: [JVMProgram] = []
            for facade in facades {
                if let index = merged.firstIndex(where: { $0.internalClassName == facade.internalClassName }) {
                    merged[index].functions += facade.functions
                    merged[index].typeAliases += facade.typeAliases
                } else { merged.append(facade) }
            }
            facades = merged
        }
        guard facades.filter(\.hasMain).count <= 1 else { throw JVMFrontendError(message: "Multiple JVM entry points in one module.") }
        // The manifest and launcher belong to the file containing main.
        if let main = facades.firstIndex(where: \.hasMain), main != 0 { facades.swapAt(0, main) }
        facadeName = facades[0].internalClassName
        var emittedClasses = try emitClasses()
        for i in emittedClasses.indices {
            emittedClasses[i] = addingSyntheticMethods(emittedClasses[i])
            if let plan = classes.values.first(where: { $0.name == emittedClasses[i].name }), let site = sema.symbols.symbol(plan.symbol)?.declSite {
                emittedClasses[i].sourceFileName = URL(fileURLWithPath: context.sourceManager.path(of: site.start.file)).lastPathComponent
            }
        }
        emittedClasses += try repeatableContainers()
        if context.options.stdlibOnly { functionArities.insert(0) }
        emittedClasses += closureClasses + functionRuntime() + enumRuntime()
        var output = facades.removeFirst()
        syntheticFunctions[coroutineIntrinsicOwner, default: []] += coroutineIntrinsics()
        output.functions += (syntheticFunctions[output.internalClassName] ?? [])
        for facade in facades {
            var type = JVMClass(name: facade.internalClassName, superclass: "java/lang/Object", interfaces: [], access: 0x31, functions: facade.functions + (syntheticFunctions[facade.internalClassName] ?? []), properties: facade.properties)
            type.isFileFacade = true; type.sourceFileName = facade.sourceFileName
            type.extraFields = facade.extraFields; type.typeAliases = facade.typeAliases
            emittedClasses.append(type)
        }
        let generatedNames = [output.internalClassName] + emittedClasses.map(\.name)
        guard Set(generatedNames).count == generatedNames.count else {
            let duplicates = Dictionary(grouping: generatedNames, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted().joined(separator: ", ")
            throw JVMFrontendError(message: "JVM generated class name clashes with a source class or facade: " + duplicates)
        }
        for functions in [output.functions] + emittedClasses.map(\.functions) {
            let signatures = functions.map { $0.reference.name + $0.reference.descriptor }
            guard Set(signatures).count == signatures.count else { throw JVMFrontendError(message: "Clashing JVM function/accessor signatures.") }
        }
        output.classes = emittedClasses
        if context.options.stdlibOnly { output.stdlibRequirements = stdlibRequirements() }
        return try lowerUnsignedConversions(lowerValueCoroutineReturns(lowerCoroutines(lowerNominalAccess(lowerValueClasses(output)))))
    }
}

final class JVMFunctionBuilder {
    struct Local { let value: JVMValue; let mutable: Bool; var cell: JVMValue? = nil; var functionType: FunctionType? = nil; var symbol: SymbolID? = nil; var delegateSymbol: SymbolID? = nil; var lateName: String? = nil; var deferredInitialization = false; var numericBoxingOrigin: JVMValue? = nil }
    struct LoopFrame {
        let label: InternedString?
        let exit: Int
        let next: Int
        let allocationDepth: Int
    }
    let program: JVMProgramBuilder
    let declaration: FunDecl
    let reference: JVMFunctionReference
    let owner: JVMClassPlan?
    var thisValue: JVMValue?
    var extensionValue: JVMValue?
    var semanticSignature: FunctionSignature?
    var functionSymbol: SymbolID?
    var leadingCaptureCount = 0
    var parameterInputs: [JVMValue]?
    var isStaticBody = false
    var isSuspendBody = false
    var lambdaID: ExprID?
    var reifiedRuntimeTokens: [SymbolID: ReifiedRuntimeToken] = [:]
    var inlineArguments: [InternedString: InlineLambda] = [:]
    var inlineReturns: [InlineReturn] = []
    var inlineStack: Set<SymbolID> = []
    var contextualReceivers: [SymbolID: JVMValue] = [:]
    var backingProperty: JVMProperty?
    var beforeDelegation = false
    var initializingObject = false
    var context: CompilationContext { program.context }
    var arena: ASTArena { program.ast.arena }
    var locals: [JVMValue] = []
    var instructions: [JVMInstruction] = []
    var scopes: [[InternedString: Local]] = [[:]]
    var loops: [LoopFrame] = []
    var pendingAllocations: [JVMValue] = []
    var handlers: [JVMExceptionHandler] = []
    struct FinallyFrame {
        let body: ExprID
        let scopes: [[InternedString: Local]]
        let loops: [LoopFrame]
        let regionDepth: Int
        let dispatch: JVMValue?
        let receiver: JVMValue?
        let contexts: [SymbolID: JVMValue]
        let arguments: [InternedString: InlineLambda]
        let returns: [InlineReturn]
        let lambda: ExprID?
    }
    var finalizers: [FinallyFrame] = []
    var activeRegions: [(start: Int?, segments: [(Int, Int)])] = []
    var evaluatedOperands: [ExprID: JVMValue] = [:]
    var tailrecEntry: Int?
    var tailrecCalls: Set<ExprID> = []
    var tailrecParameters: [JVMValue] = []
    var nextSlot = 0
    var nextLabel = 0
    var terminated = false

    init(program: JVMProgramBuilder, declaration: FunDecl, reference: JVMFunctionReference, owner: JVMClassPlan? = nil) {
        self.program = program; self.declaration = declaration; self.reference = reference; self.owner = owner
    }
    func fail(_ message: String, _ id: ExprID? = nil) -> JVMFrontendError {
        JVMFrontendError(message: message, range: id.flatMap(arena.exprRange) ?? declaration.range)
    }
    func value(_ type: JVMValueType) throws -> JVMValue {
        guard type != .unit, nextSlot + type.width <= 65_535 else { throw fail("JVM local-variable slot limit exceeded or Unit used as a value.") }
        let result = JVMValue(slot: nextSlot, type: type)
        nextSlot += type.width; locals.append(result)
        return result
    }
    func label() -> Int { defer { nextLabel += 1 }; return nextLabel }
    func mark(_ label: Int) { instructions.append(.label(label)); terminated = false }
    func jump(_ label: Int) { instructions.append(.jump(label)); terminated = true }
    func lookup(_ name: InternedString) throws -> Local {
        for scope in scopes.reversed() { if let local = scope[name] { return local } }
        throw fail("JVM local variable is not in scope: \(context.interner.resolve(name)).")
    }
    func requireValue(_ id: ExprID) throws -> JVMValue {
        let result = try expression(id)
        if terminated { throw JVMTerminatedExpression() }
        if result == nil, program.sema.bindings.exprType(for: id) == program.sema.types.unitType {
            program.functionArities.insert(0)
            let unit: JVMValueType = .reference("kotlin/Unit", nullable: false), result = try value(unit)
            instructions.append(.getStatic(JVMField(owner: "kotlin/Unit", name: "INSTANCE", type: unit, access: 0x19), result))
            return result
        }
        guard let result else { throw fail("JVM value expression does not produce a supported value.", id) }
        return result
    }
    func localStorageType(_ semantic: TypeID) throws -> JVMValueType {
        let type = try program.type(semantic)
        if type == .unit {
            program.functionArities.insert(0)
            return .reference("kotlin/Unit", nullable: false)
        }
        return type
    }
    func erasedLocalStorageType(_ semantic: TypeID) throws -> JVMValueType {
        let type = try program.erasedType(semantic)
        if type == .unit {
            program.functionArities.insert(0)
            return .reference("kotlin/Unit", nullable: false)
        }
        return type
    }
    func convert(_ source: JVMValue, to type: JVMValueType) throws -> JVMValue {
        if source.type == type { return source }
        if source.type.referenceName != nil, type.isNumeric,
           let carrier = source.type.numericCarrier, carrier != type {
            // Unbox the actual wrapper before widening; casting Byte to
            // Integer (or Float to Double) would fail at runtime.
            return try convert(convert(source, to: carrier), to: type)
        }
        guard (source.type.isNumeric && type.isNumeric) || (source.type.referenceName != nil && type.referenceName != nil) || (type.referenceName != nil && source.type != .unit) || (source.type.referenceName != nil && (type.isNumeric || type == .boolean)) else { throw fail("Unsupported JVM value conversion.") }
        let result = try value(type); instructions.append(.copy(source, result)); return result
    }
    func constant(_ constant: JVMConstant, _ type: JVMValueType) throws -> JVMValue {
        let result = try value(type); instructions.append(.constant(constant, result)); return result
    }
    func prepareParameters() throws {
        if let owner, !isStaticBody { thisValue = try value(.reference(owner.name, nullable: false)) }
        var parameters = Array(reference.parameters.dropFirst(leadingCaptureCount))
        var supplied = parameterInputs
        guard supplied == nil || supplied!.count == parameters.count else { throw fail("JVM prepared parameter count mismatch.") }
        if declaration.receiverType != nil {
            guard let first = parameters.first else { throw fail("Missing JVM extension receiver.") }
            extensionValue = try supplied == nil ? value(first) : supplied!.removeFirst()
            parameters.removeFirst()
        }
        if let owner, let thisValue {
            contextualReceivers[owner.symbol] = thisValue
            contextualReceivers[SyntheticSymbolScheme.receiverParameterSymbol(for: owner.symbol)] = thisValue
        }
        if let functionSymbol, let receiver = extensionValue ?? thisValue { contextualReceivers[SyntheticSymbolScheme.receiverParameterSymbol(for: functionSymbol)] = receiver }
        for (i, pair) in zip(declaration.valueParams, parameters).enumerated() {
            let (param, type) = pair
            var local = Local(value: try supplied?[i] ?? value(type), mutable: false)
            if let signature = semanticSignature, signature.parameterTypes.indices.contains(i), case let .functionType(f) = program.sema.types.kind(of: signature.parameterTypes[i]) { local.functionType = f }
            if let signature = semanticSignature, signature.valueParameterSymbols.indices.contains(i) { local.symbol = signature.valueParameterSymbols[i] }
            scopes[0][param.name] = local
        }
        if reference.name != "<init>" && !isStaticBody { try prepareEnclosingInstances() }
    }
    func finish(abstract: Bool = false, constructor: Bool = false) -> JVMFunction {
        var function = JVMFunction(reference: reference, isPrivate: declaration.modifiers.contains(.private), locals: locals, parameterCount: reference.parameters.count + (owner == nil || isStaticBody ? 0 : 1), instructions: instructions, parameterNames: declaration.valueParams.map { context.interner.resolve($0.name) }, isInternal: declaration.modifiers.contains(.internal))
        function.owner = owner?.name ?? program.facadeName
        if let owner {
            function.access = program.access(declaration.modifiers, final: !owner.isInterface && !constructor && program.memberFinal(declaration.modifiers)) | (abstract ? 0x0400 : 0)
        }
        // Public synthetic helpers remain accessible when a consuming Kotlin
        // compiler moves an inline function's closure allocation to another package.
        if isStaticBody { function.access = 0x1009; function.isSynthetic = true }
        function.isSuspend = declaration.isSuspend || isSuspendBody
        function.isInline = declaration.isInline
        // Sema includes modifiers inherited by overrides in the symbol flags.
        let semanticFlags = functionSymbol.flatMap { program.sema.symbols.symbol($0)?.flags }
        function.isOperator = declaration.modifiers.contains(.operator) || semanticFlags?.contains(.operatorFunction) == true
        function.isInfix = declaration.modifiers.contains(.infix) || semanticFlags?.contains(.infixFunction) == true
        // This backend retains crossinline callbacks as function objects.
        // Export that physical requirement as noinline so Kotlin's bytecode
        // inliner does not erase an object passed to a lifted lambda helper.
        function.parameterDefaultFlags = declaration.valueParams.map(\.hasDefaultValue)
        function.parameterInlineFlags = declaration.valueParams.map { $0.isCrossinline || $0.isNoinline ? 8 : 0 }
        function.handlers = handlers
        function.isConstructor = constructor; function.isAbstract = abstract
        return function
    }
    func build() throws -> JVMFunction {
        try prepareParameters()
        if declaration.modifiers.contains(.abstract) || (owner?.isInterface == true && declaration.body == .unit) { return finish(abstract: true) }
        try prepareTailrec()
        // A function body may shadow a parameter, as ordinary nested blocks do.
        scopes.append([:])
        switch declaration.body {
        case let .block(statements, _):
            for statement in statements where !terminated { _ = try expression(statement, discarded: true) }
        case let .expr(id, _):
            let result = try expression(id, discarded: reference.result == .unit)
            if !terminated {
                if reference.result == .unit { instructions.append(.returnValue(nil)) }
                else {
                    guard let result else { throw fail("JVM function must return a value.", id) }
                    instructions.append(.returnValue(try convert(result, to: reference.result)))
                }
                terminated = true
            }
        case .unit: throw fail("JVM functions require a body.")
        }
        if !terminated {
            guard reference.result == .unit else { throw fail("JVM non-Unit function must return on every path.") }
            instructions.append(.returnValue(nil))
        }
        return finish()
    }

    func rawExpression(_ id: ExprID, discarded: Bool = false) throws -> JVMValue? {
        if program.sema.bindings.stdlibSpecialCallKinds[id] == .contract { return nil }
        guard let expr = arena.expr(id) else { throw fail("Missing JVM expression.", id) }
        switch expr {
        case let .inExpr(lhs, rhs, _), let .notInExpr(lhs, rhs, _):
            // Operator expansion evaluates the container before its element.
            let container = try requireValue(rhs), element = try requireValue(lhs)
            let saved = evaluatedOperands
            evaluatedOperands[rhs] = container; evaluatedOperands[lhs] = element
            defer { evaluatedOperands = saved }
            let args = [CallArgument(expr: lhs)]
            let call = try inlineCall(args, receiver: rhs, id: id) ?? sourceCall(args, receiver: rhs, id: id) ?? textLibraryCall(args, receiver: rhs, id: id) ?? intrinsicMember(rhs, name: context.interner.intern("contains"), args: args, id: id)
            guard let result = call?.value else { throw fail("Unsupported JVM membership receiver.", id) }
            if case .notInExpr = expr { let negated = try value(.boolean); instructions.append(.unary(.not, result, negated)); return negated }
            return result
        case .objectLiteral: return try anonymousObject(id)
        case let .whenExpr(subject, branches, fallback, _): return try whenExpression(id, subject: subject, branches: branches, fallback: fallback, discarded: discarded)
        case let .destructuringDecl(names, mutable, initializer, _): try destructuring(id, names: names, mutable: mutable, initializer: initializer); return nil
        case let .intLiteral(number, _):
            let type = try program.expressionType(id)
            if type == .long { return try constant(.long(number), .long) }
            guard let n = Int32(exactly: number), [.int, .byte, .short].contains(type) else { throw fail("JVM Int literal is out of range.", id) }
            return try constant(.int(n), type)
        case let .charLiteral(scalar, _): return try constant(.int(Int32(scalar)), .char)
        case let .uintLiteral(number, _), let .ulongLiteral(number, _):
            let type = try program.expressionType(id)
            return try constant(type == .ulong ? .long(Int64(bitPattern: number)) : .int(Int32(truncatingIfNeeded: number)), type)
        case let .longLiteral(number, _): return try constant(.long(number), .long)
        case let .floatLiteral(number, _): return try constant(.float(Float(number)), .float)
        case let .doubleLiteral(number, _): return try constant(.double(number), .double)
        case let .boolLiteral(b, _): return try constant(.boolean(b), .boolean)
        case .nullLiteral: return try constant(.null, .reference("java/lang/Object", nullable: true))
        case let .nullAssert(operand, _):
            let source = try requireValue(operand)
            guard source.type.referenceName != nil else { return source }
            let target = try program.expressionType(id)
            let nonNull = label()
            let null = try constant(.null, source.type), check = try value(.boolean)
            instructions.append(.referenceCompare(.equal, source, null, check))
            instructions.append(.jumpIfFalse(check, nonNull))
            instructions.append(.throwValue(try constructJDK("java/lang/NullPointerException")))
            terminated = true
            mark(nonNull)
            return try convert(source, to: target)
        case let .stringTemplate(parts, _): return try stringTemplate(parts)
        case let .stringLiteral(s, _): return try constant(.string(context.interner.resolve(s)), .string)
        case .thisRef, .superRef:
            if case .thisRef = expr, let symbol = program.sema.bindings.identifierSymbol(for: id), let receiver = contextualReceivers[symbol] { return try convert(receiver, to: program.expressionType(id)) }
            if case .thisRef = expr, let extensionValue { return try convert(extensionValue, to: program.expressionType(id)) }
            guard !beforeDelegation, let thisValue else { throw fail("JVM this/super requires an initialized instance.", id) }
            if case .thisRef = expr { return try convert(thisValue, to: program.expressionType(id)) }
            return thisValue
        case let .nameRef(name, _):
            if let value = try nominalValue(id) { return value }
            if let symbol = program.sema.bindings.identifierSymbol(for: id),
               program.sema.symbols.symbol(symbol)?.fqName.map(context.interner.resolve) == ["kotlin", "Unit"] {
                program.functionArities.insert(0)
                let type: JVMValueType = .reference("kotlin/Unit", nullable: false), result = try value(type)
                instructions.append(.getStatic(JVMField(owner: "kotlin/Unit", name: "INSTANCE", type: type, access: 0x19), result))
                return result
            }
            if let symbol = program.sema.bindings.identifierSymbol(for: id),
               program.sema.symbols.symbol(symbol)?.fqName.map(context.interner.resolve) == ["kotlin", "coroutines", "EmptyCoroutineContext"] {
                let type: JVMValueType = .reference("kotlin/coroutines/EmptyCoroutineContext", nullable: false), result = try value(type)
                instructions.append(.getStatic(JVMField(owner: "kotlin/coroutines/EmptyCoroutineContext", name: "INSTANCE", type: type, access: 0x19), result))
                return result
            }
            if let property = backingProperty, context.interner.resolve(name) == "field", !scopes.contains(where: { $0[name] != nil }) {
                guard let field = property.field else { throw fail("JVM accessor has no backing field.", id) }
                let result = try value(field.type)
                if property.getter.isStatic { instructions.append(.getStatic(field, result)) }
                else { instructions.append(.getField(field, thisValue!, result)) }; return result
            }
            if let result = try implicitReceiverProperty(id, name: name) { return result }
            if !scopes.contains(where: { $0[name] != nil }), let property = propertyBinding(id) {
                if let literal = property.field?.constantValue { return try constant(literal, property.type) }
                return try convert(readProperty(property, receiver: instance(id), special: false), to: program.expressionType(id))
            }
            if !scopes.contains(where: { $0[name] != nil }), let result = try textLibraryProperty(id) { return result }
            // Snapshot reads before evaluating later operands/arguments, which
            // may mutate the same source variable (for example f(x, x++)).
            let local = try readLocal(lookup(name))
            let type = try program.expressionType(id)
            return type == .unit ? local : try convert(local, to: type)
        case .localFunDecl:
            try localFunction(id); return nil
        case .localNominalDecl:
            return nil
        case let .localDecl(name, mutable, annotation, initializer, delegated, late, _):
            if delegated || late { try specialLocal(id, name: name, mutable: mutable, initializer: initializer, delegated: delegated, late: late); return nil }
            guard scopes[scopes.count - 1][name] == nil else { throw fail("JVM locals require a unique name in their scope.", id) }
            let symbol = program.sema.bindings.identifierSymbol(for: id)
            if let symbol, let initializer, program.hasSourceRangeOperator(initializer) {
                program.sourceRangeResultSymbols.insert(symbol)
            }
            let semanticType = symbol.flatMap { program.sema.symbols.propertyType(for: $0) }
                ?? initializer.flatMap { program.sema.bindings.exprType(for: $0) }
            let declaredType: JVMValueType?
            if annotation != nil {
                guard let type = semanticType else { throw fail("Missing JVM local type binding.", id) }
                declaredType = try localStorageType(type)
            } else if let semanticType, case .functionType = program.sema.types.kind(of: semanticType) {
                // Distinct generated callable classes share their inferred function storage.
                declaredType = try localStorageType(semanticType)
            } else { declaredType = nil }
            let initial = try initializer.map { try requireValue($0) }
            guard let storageType = declaredType ?? initial?.type else { throw fail("Missing JVM local type binding.", id) }
            let local = try value(storageType)
            if let initial { instructions.append(.copy(try convert(initial, to: local.type), local)) }
            var binding = Local(value: local, mutable: mutable)
            binding.symbol = symbol
            if !mutable, local.type.referenceName == "java/lang/Comparable",
               let initial, initial.type.isNumeric {
                // Retain the evaluated primitive behind this immutable box.
                // Closure helpers deliberately reconstruct locals without it.
                binding.numericBoxingOrigin = initial
            }
            binding.deferredInitialization = initial == nil && !mutable
            // Sema owns definite assignment, including mutually exclusive val
            // writes. Deferred callback initialization needs the same shared
            // storage as a mutable captured local.
            if mutable || (initializer == nil && symbol.map { program.sema.bindings.isContractCallsInPlaceInitializedSymbol($0) } == true) {
                let element = try binding.symbol.flatMap { program.sema.bindings.capturedLocalType(for: $0) }.map { try erasedLocalStorageType($0) } ?? local.type
                let cell = try value(.reference("[" + element.descriptor, nullable: false)), count = try constant(.int(1), .int), index = try constant(.int(0), .int)
                instructions.append(.newArray(element, count: count, result: cell))
                if initial != nil { instructions.append(.arraySet(cell, index, local)) }
                binding.cell = cell
            }
            if let semantic = semanticType ?? initializer.flatMap({ program.sema.bindings.exprType(for: $0) }), case let .functionType(f) = program.sema.types.kind(of: semantic) { binding.functionType = f }
            scopes[scopes.count - 1][name] = binding
            return nil
        case let .localAssign(name, rhs, _):
            if let property = backingProperty, context.interner.resolve(name) == "field", !scopes.contains(where: { $0[name] != nil }) {
                guard let field = property.field else { throw fail("Missing JVM backing field.", id) }
                let result = try convert(requireValue(rhs), to: field.type)
                instructions.append(property.getter.isStatic ? .putStatic(field, result) : .putField(field, thisValue!, result)); return nil
            }
            if !scopes.contains(where: { $0[name] != nil }), let property = propertyBinding(id) {
                let object = try instance(id), result = try requireValue(rhs)
                try writeProperty(property, receiver: object, value: result, initializing: reference.name == "<init>" || initializingObject)
                return nil
            }
            let local = try lookup(name)
            guard local.mutable || local.deferredInitialization else { throw fail("Cannot reassign JVM val.", id) }
            let result = try convert(requireValue(rhs), to: local.value.type)
            try writeLocal(local, result)
            return arena.incrementDecrementReturnsValue(id) ? result : nil
        case let .compoundAssign(op, name, rhs, _):
            if let property = backingProperty, context.interner.resolve(name) == "field", !scopes.contains(where: { $0[name] != nil }) {
                guard let field = property.field else { throw fail("Missing JVM backing field.", id) }
                let left = try value(field.type)
                instructions.append(property.getter.isStatic ? .getStatic(field, left) : .getField(field, thisValue!, left))
                if let call = try resolvedCompoundCall(op, receiver: left, rhs: rhs, id: id) {
                    if !call.mutatesReceiver, let result = call.value, !terminated {
                        let converted = try convert(result, to: field.type)
                        instructions.append(property.getter.isStatic ? .putStatic(field, converted) : .putField(field, thisValue!, converted))
                    }
                    return nil
                }
                let right = try compoundOperand(rhs, target: field.type)
                if terminated { return nil }
                guard try permitsCompound(left.type, right.type) else { throw fail("Unsupported JVM backing field conversion.", id) }
                let converted = right, result = try value(field.type)
                let operators: [CompoundAssignOp: BinaryOp] = [.plusAssign: .add, .minusAssign: .subtract, .timesAssign: .multiply, .divAssign: .divide, .modAssign: .modulo]
                try compoundInstruction(operators[op]!, left, converted, result)
                instructions.append(property.getter.isStatic ? .putStatic(field, result) : .putField(field, thisValue!, result))
                return arena.incrementDecrementReturnsValue(id) ? result : nil
            }
            if !scopes.contains(where: { $0[name] != nil }), let property = propertyBinding(id) {
                return try propertyCompound(property, receiver: instance(id), op: op, rhs: rhs, id: id)
            }
            let local = try lookup(name)
            let loaded = try readLocal(local), old = try value(loaded.type)
            // The RHS may reassign this local before the operator call executes.
            instructions.append(.copy(loaded, old))
            if let call = try resolvedCompoundCall(op, receiver: old, rhs: rhs, id: id) {
                if !call.mutatesReceiver, !terminated {
                    guard local.mutable, let result = call.value else { throw fail("Cannot reassign JVM val.", id) }
                    try writeLocal(local, convert(result, to: local.value.type))
                }
                return nil
            }
            guard local.mutable, local.value.type.isNumeric || local.value.type.isText else { throw fail("JVM compound assignment requires a mutable numeric local.", id) }
            let rawRight = try compoundOperand(rhs, target: old.type)
            if terminated { return nil }
            guard try permitsCompound(old.type, rawRight.type) else { throw fail("JVM compound assignment cannot narrow its numeric result.", id) }
            let right = rawRight
            let result = try value(old.type)
            let binary: BinaryOp
            switch op {
            case .plusAssign: binary = .add
            case .minusAssign: binary = .subtract
            case .timesAssign: binary = .multiply
            case .divAssign: binary = .divide
            case .modAssign: binary = .modulo
            }
            try compoundInstruction(binary, old, right, result); try writeLocal(local, result)
            return arena.incrementDecrementReturnsValue(id) ? result : nil
        case let .binary(op, lhs, rhs, _): return try binary(op, lhs, rhs, id)
        case let .unaryExpr(op, operand, _):
            if let call = try inlineCall([], receiver: operand, id: id)
                ?? sourceCall([], receiver: operand, id: id) { return call.value }
            if op == .unaryMinus, case let .intLiteral(n, _) = arena.expr(operand), n == 2_147_483_648,
               try program.expressionType(id) == .int { return try constant(.int(.min), .int) }
            let source = try requireValue(operand)
            guard (op == .not && source.type == .boolean) || (op != .not && source.type.isNumeric) else { throw fail("Unsupported JVM unary operand.", id) }
            let type = try program.expressionType(id), operand = try convert(source, to: type)
            let result = try value(type); instructions.append(.unary(op, operand, result)); return result
        case let .call(callee, _, args, _):
            if program.sema.bindings.callBinding(for: id) == nil, args.count == 1,
               let target = program.sema.bindings.samInterfaceType(for: args[0].expr), target == program.sema.bindings.exprType(for: id) {
                return try expression(args[0].expr)
            }
            if program.sema.bindings.stdlibSpecialCallKinds[id] == .arrayConstructor {
                return try arrayConstructor(args, id: id)
            }
            if let value = try nominalCall(id, receiver: nil, name: nil, args: args) { return value.value }
            let invokeReceiver: ExprID?
            if let binding = program.sema.bindings.callBinding(for: id), context.interner.resolve(program.sema.symbols.symbol(binding.chosenCallee)?.name ?? context.interner.intern("")) == "invoke", program.sema.bindings.identifierSymbol(for: callee).flatMap({ program.sema.symbols.symbol($0) })?.kind != .function {
                invokeReceiver = callee
            } else { invokeReceiver = nil }
            if let result = try inlineCall(args, receiver: invokeReceiver, id: id) { return result.value }
            if let result = try textLibraryCall(args, receiver: invokeReceiver, id: id) { return result.value }
            if let result = try sourceCall(args, receiver: invokeReceiver, id: id) { return result.value }
            if invokeReceiver == nil, let result = try implicitTextCall(callee, args: args, id: id) { return result.value }
            if let function = try functionValueCall(callee, args: args, id: id) { return function.value }
            guard args.allSatisfy({ !$0.isSpread }),
                  let binding = program.sema.bindings.callBinding(for: id) else { throw fail("Unsupported JVM call.", id) }
            if let result = try implicitExtensionCall(binding.chosenCallee, args: args, id: id) { return result.value }
            if let result = try implicitCollectionIteratorCall(binding.chosenCallee, args: args, id: id) { return result.value }
            if let result = try intrinsicCall(binding.chosenCallee, args: args, id: id) { return result.value }
            if let method = program.methods[binding.chosenCallee] ?? context.jvmImports?.methods[binding.chosenCallee] {
                return try foreign(method, receiver: method.isConstructor || method.isStatic ? nil : instance(id), args: args, id: id)
            }
            if let function = program.references[binding.chosenCallee] {
                guard args.count == function.parameters.count else { throw fail("JVM argument count mismatch.", id) }
                var values: [JVMValue] = []
                for (arg, type) in zip(args, function.parameters) { values.append(try convert(requireValue(arg.expr), to: type)) }
                let result = function.result == .unit ? nil : try value(function.result)
                instructions.append(.call(function, values, result)); return try result.map { try convert($0, to: program.expressionType(id)) }
            }
            guard let symbol = program.sema.symbols.symbol(binding.chosenCallee),
                  let site = symbol.declSite,
                  context.sourceManager.path(of: site.start.file) == JVMPreparationPhase.consolePath else { throw fail("JVM M6 can call only source functions and print/println.", id) }
            let name = context.interner.resolve(symbol.name)
            guard ["print", "println"].contains(name), args.count <= 1 else { throw fail("Unsupported JVM console call.", id) }
            let argument = try args.first.map { try requireValue($0.expr) }
            instructions.append(.print(argument, newline: name == "println")); return nil
        case let .memberAssign(receiver, _, rhs, _):
            guard let property = propertyBinding(id) else { throw fail("Missing JVM property assignment binding.", id) }
            let object = try property.getter.isStatic && property.getter.parameters.isEmpty
                ? constant(.null, .reference("java/lang/Object", nullable: true))
                : requireValue(receiver)
            let result = try requireValue(rhs)
            try writeProperty(property, receiver: object, value: result, initializing: reference.name == "<init>" || initializingObject, special: isSuper(receiver), superReceiver: receiver)
            return nil
        case let .memberCompoundAssign(op, receiver, _, rhs, _):
            guard let property = propertyBinding(id) else { throw fail("Missing JVM property assignment binding.", id) }
            return try propertyCompound(property, receiver: requireValue(receiver), op: op, rhs: rhs, id: id, special: isSuper(receiver), superReceiver: receiver)
        case let .memberCall(receiver, name, typeArgs, args, _):
            return try memberExpression(id, receiver: receiver, name: name, typeArgs: typeArgs, args: args)
        case let .safeMemberCall(receiver, name, typeArgs, args, _):
            return try safeMemberExpression(id, receiver: receiver, name: name, typeArgs: typeArgs, args: args, discarded: discarded)
        case .lambdaLiteral: return try closure(id)
        case let .callableRef(receiver, member, _): return try reflectionReference(id, receiver: receiver, member: member)
        case let .asCast(source, _, safe, _):
            return try checkedCast(source, safe: safe, id: id)
        case let .isCheck(source, target, negated, _):
            return try instanceCheck(source, target: target, negated: negated, id: id)
        case let .indexedAccess(receiver, indices, _): return try indexedGet(receiver, indices, id)
        case let .indexedAssign(receiver, indices, source, _): try indexedSet(receiver, indices, source, id); return nil
        case let .indexedCompoundAssign(op, receiver, indices, source, _): return try indexedCompound(op, receiver, indices, source, id)
        case let .tryExpr(body, catches, finalizer, _): return try tryExpression(id, body, catches, finalizer, discarded: discarded)
        case let .throwExpr(source, _):
            let thrown = try requireValue(source)
            instructions.append(.throwValue(thrown)); terminated = true; return nil
        case let .blockExpr(statements, trailing, _):
            scopes.append([:]); defer { scopes.removeLast() }
            var result: JVMValue?
            for statement in statements where !terminated { _ = try expression(statement, discarded: true) }
            if let trailing, !terminated { result = try expression(trailing, discarded: discarded) }
            return result
        case let .ifExpr(condition, thenExpr, elseExpr, _): return try conditional(id, condition, thenExpr, elseExpr, discarded: discarded)
        case let .whileExpr(condition, body, label, _):
            let test = self.label(), exit = self.label()
            mark(test); let check = try requireValue(condition)
            guard check.type == .boolean else { throw fail("JVM while condition must be Boolean.", id) }
            instructions.append(.jumpIfFalse(check, exit)); loops.append(LoopFrame(label: label, exit: exit, next: test, allocationDepth: pendingAllocations.count))
            _ = try expression(body, discarded: true); loops.removeLast()
            if !terminated { jump(test) }; mark(exit); return nil
        case let .doWhileExpr(body, condition, label, _):
            let start = self.label(), test = self.label(), exit = self.label()
            scopes.append([:]); defer { scopes.removeLast() }
            mark(start); loops.append(LoopFrame(label: label, exit: exit, next: test, allocationDepth: pendingAllocations.count))
            // Kotlin keeps do-body declarations visible in its condition.
            if case let .blockExpr(statements, trailing, _) = arena.expr(body) {
                for statement in statements where !terminated { _ = try expression(statement, discarded: true) }
                if let trailing, !terminated { _ = try expression(trailing, discarded: true) }
            } else { _ = try expression(body, discarded: true) }
            if terminated, !instructions.contains(where: { if case let .jump(target) = $0 { return target == test }; return false }) {
                loops.removeLast()
                if instructions.contains(where: { if case let .jump(target) = $0 { return target == exit }; return false }) { mark(exit) }
                return nil
            }
            mark(test); let check = try expression(condition)
            loops.removeLast()
            if !terminated {
                guard let check, check.type == .boolean else { throw fail("JVM do-while condition must be Boolean.", id) }
                instructions.append(.jumpIfFalse(check, exit)); jump(start); mark(exit)
            } else if instructions.contains(where: { if case let .jump(target) = $0 { return target == exit }; return false }) {
                // A break in the body can still reach the exit when evaluating
                // the condition returns or throws on the other path.
                mark(exit)
            }
            return nil
        case let .forExpr(name, iterable, body, label, _):
            guard let name else { throw fail("Unsupported JVM for loop.", id) }
            try forLoop(name, iterable, body, id, label: label); return nil
        case let .breakExpr(label, _), let .continueExpr(label, _):
            let targetIndex: Int?
            if let label {
                targetIndex = loops.lastIndex { $0.label == label }
            } else {
                targetIndex = loops.indices.last
            }
            guard let targetIndex else { throw fail("JVM break/continue requires a matching enclosing loop.", id) }
            let loop = loops[targetIndex]
            instructions.append(.abandonAllocations(Array(pendingAllocations.dropFirst(loop.allocationDepth))))
            try emitFinalizers(leavingLoop: targetIndex + 1)
            if terminated { return nil }
            if case .breakExpr = expr { jump(loop.exit) } else { jump(loop.next) }; return nil
        case let .returnExpr(returned, label, _):
            if try inlineReturn(id, returned: returned) { return nil }
            if let lambdaID {
                guard program.sema.bindings.lambdaReturnTargets[id] == lambdaID else { throw fail("JVM M6 supports returns local to the current lambda.", id) }
            } else if label != nil { throw fail("JVM return labels require a lambda.", id) }
            if reference.result == .unit {
                if let returned { _ = try expression(returned) }
                if !terminated { try emitFinalizers(); if !terminated { instructions.append(.returnValue(nil)) } }
            } else {
                guard let returned else { throw fail("JVM function must return a value.", id) }
                let result = try convert(requireValue(returned), to: reference.result)
                try emitFinalizers()
                if !terminated { instructions.append(.returnValue(result)) }
            }
            terminated = true; return nil
        default: throw fail("Expression is outside the JVM M6 subset.", id)
        }
    }
}

extension JVMFunctionBuilder {
    func foreign(_ method: JVMForeignMethod, receiver: JVMValue?, args: [CallArgument], id: ExprID) throws -> JVMValue? {
        if method.isConstructor, program.classes.values.contains(where: { $0.name == method.owner && $0.isEnum }) {
            throw fail("JVM enum constructors can only initialize enum entries.", id)
        }
        guard args.count == method.parameters.count, !(method.isConstructor && (context.jvmImports?.classes[method.owner]?.flags ?? 0) & 0x0400 != 0) else { throw fail("Unsupported JVM constructor or argument count.", id) }
        var object = receiver
        if let receiver, receiver.type.referenceName == nil { object = try convert(receiver, to: .reference("java/lang/Object", nullable: false)) }
        if method.isConstructor {
            object = try value(method.result)
            instructions.append(.allocate(method.owner, object!))
            pendingAllocations.append(object!)
        }
        defer { if method.isConstructor { pendingAllocations.removeLast() } }
        var values: [JVMValue] = []
        for (index, pair) in zip(args, method.parameters).enumerated() {
            let (arg, type) = pair
            var source = try requireValue(arg.expr)
            // Imported static methods are represented by companion stubs.
            // Retain the resolved nominal target even if their SAM adaptation
            // was inferred through the ordinary member-call path.
            if source.type.referenceName?.hasPrefix("kotlin/jvm/functions/Function") == true,
               let binding = program.sema.bindings.callBinding(for: id),
               let signature = program.sema.symbols.functionSignature(for: binding.chosenCallee),
               signature.parameterTypes.indices.contains(index),
               case let .classType(target) = program.sema.types.kind(of: signature.parameterTypes[index]),
               program.sema.symbols.symbol(target.classSymbol)?.flags.contains(.funInterface) == true,
               TypeCheckHelpers().effectiveSamAbstractMethod(for: target.classSymbol, symbols: program.sema.symbols) != nil {
                source = try adaptSAM(source, target: signature.parameterTypes[index], at: arg.expr)
            }
            values.append(try convert(source, to: type))
        }
        let resultType = method.isConstructor ? method.result : try program.expressionType(id)
        let result = method.isConstructor || method.result == .unit || resultType == .unit ? nil : try value(resultType)
        instructions.append(.foreignCall(method, receiver: object, arguments: values, result: result))
        return method.isConstructor ? object : result
    }
}

import Foundation

/// Classpath lookup follows the caller's entry order. ZIP decoding is shared
/// with KLIB, including bounded entry reads and CRC validation.
final class JVMClasspathIndex {
    var classes: [String: JVMClassInfo] = [:]
    var sourceClasses: [FileID: JVMClassInfo] = [:]
    var methods: [SymbolID: JVMForeignMethod] = [:]
    var extensionSymbols: Set<SymbolID> = []
    private var hierarchyClasses: [String: JVMClassInfo] = [:]

    static func load(_ paths: [String]) throws -> JVMClasspathIndex {
        let result = JVMClasspathIndex()
        var seen: Set<String> = []
        func insert(_ bytes: [UInt8], path: String) throws {
            var reader = JVMClassReader(bytes: bytes)
            let info = try reader.read()
            guard info.name + ".class" == path else { throw JVMFrontendError(message: "JVM class name does not match entry path: \(info.name) in \(path)") }
            guard seen.insert(info.name).inserted else { return }
            result.hierarchyClasses[info.name] = info
            guard info.flags & 1 != 0, !info.name.contains("$"),
                  info.name.split(separator: "/").allSatisfy({ JVMProgramBuilder.isIdentifier(String($0)) }) else { return }
            if result.classes[info.name] == nil { result.classes[info.name] = info }
        }
        for path in paths {
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &directory) else {
                throw JVMFrontendError(message: "JVM classpath entry does not exist: \(path)")
            }
            if directory.boolValue {
                let base = URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath()
                guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) else { throw JVMClassReader.Invalid() }
                let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "class" }.sorted { $0.path < $1.path }
                for file in files {
                    let relative = file.resolvingSymlinksInPath().pathComponents.dropFirst(base.pathComponents.count).joined(separator: "/")
                    guard !relative.hasPrefix("META-INF/"), !relative.hasSuffix("module-info.class"), !relative.hasSuffix("package-info.class") else { continue }
                    try insert(Array(Data(contentsOf: file)), path: relative)
                }
            } else {
                let archive = try ZipArchive(data: Data(contentsOf: URL(fileURLWithPath: path)))
                for entry in archive.entries.sorted(by: { $0.name < $1.name }) {
                    guard entry.name.hasSuffix(".class"), !entry.name.hasPrefix("META-INF/"),
                          !entry.name.hasSuffix("module-info.class"), !entry.name.hasSuffix("package-info.class") else { continue }
                    try insert(archive.contents(of: entry), path: entry.name)
                }
            }
        }
        result.importInheritedMembers()
        return result
    }
    private func importInheritedMembers() {
        func key(_ method: JVMForeignMethod) -> String {
            method.name + method.descriptor.prefix(through: method.descriptor.firstIndex(of: ")")!)
        }
        func accessibleMethod(_ method: JVMForeignMethod, on info: JVMClassInfo) -> JVMForeignMethod {
            var result = JVMForeignMethod(owner: info.name, name: method.name, descriptor: method.descriptor, parameters: method.parameters,
                                          result: method.result, isStatic: method.isStatic, isInterface: info.isInterface, isAbstract: method.isAbstract)
            result.isFinal = method.isFinal; result.isSpecial = method.isSpecial; result.isSuspend = method.isSuspend
            return result
        }
        func interfaceInherits(_ subtype: String, _ supertype: String, visited: Set<String> = []) -> Bool {
            if subtype == supertype { return true }
            guard !visited.contains(subtype), let info = hierarchyClasses[subtype] else { return false }
            return info.interfaces.contains { interfaceInherits($0, supertype, visited: visited.union([subtype])) }
        }
        for info in classes.values {
            var methods = info.methods
            var bridges = info.bridgeMethods
            var interfaces: [String] = []
            var inheritedInterfaces = info.interfaces
            var interfaceVisited: Set<String> = []
            var interfaceMethods: [String: JVMForeignMethod] = [:]
            func inheritInterface(_ name: String) {
                guard interfaceVisited.insert(name).inserted, let base = hierarchyClasses[name] else { return }
                if classes[name] != nil { interfaces.append(name); return }
                bridges += base.bridgeMethods
                for method in base.methods where !method.isStatic && !method.isConstructor {
                    let signature = key(method)
                    if !methods.contains(where: { key($0) == signature }),
                       interfaceMethods[signature].map({ interfaceInherits(method.owner, $0.owner) }) ?? true {
                        // The most specific interface wins independently of the
                        // order of redundant interfaces in the classfile.
                        interfaceMethods[signature] = method
                    }
                }
                for parent in base.interfaces { inheritInterface(parent) }
            }
            var visited: Set<String> = [info.name]
            var next = info.superclass
            var superclass: String?
            var hiddenSegment = true
            while let name = next, visited.insert(name).inserted, let base = hierarchyClasses[name] {
                let visible = classes[name] != nil
                if visible && superclass == nil { superclass = name; hiddenSegment = false }
                for method in base.methods where !method.isConstructor && (method.isStatic || hiddenSegment) {
                    if !methods.contains(where: { key($0) == key(method) }) {
                        // A method reference must name an accessible class even
                        // when its implementation is inherited from a hidden base.
                        methods.append(visible ? method : accessibleMethod(method, on: info))
                    }
                }
                if hiddenSegment {
                    bridges += base.bridgeMethods
                    inheritedInterfaces += base.interfaces
                }
                next = base.superclass
            }
            for name in inheritedInterfaces { inheritInterface(name) }
            methods += interfaceMethods.keys.sorted().map { accessibleMethod(interfaceMethods[$0]!, on: info) }
            var abstractMethods: Set<String> = []
            var abstractVisited: Set<String> = []
            func collectAbstract(_ name: String) {
                guard abstractVisited.insert(name).inserted, let base = hierarchyClasses[name] else { return }
                for method in base.methods where method.isAbstract { abstractMethods.insert(key(method)) }
                for parent in base.interfaces { collectAbstract(parent) }
                if let parent = base.superclass { collectAbstract(parent) }
            }
            for name in interfaces { collectAbstract(name) }
            if let superclass { collectAbstract(superclass) }
            // Erased imports need a real bridge when an inherited raw method
            // has different parameters from the specialized implementation.
            for bridge in bridges where abstractMethods.contains(key(bridge)) && !methods.contains(where: { key($0) == key(bridge) }) {
                methods.append(accessibleMethod(bridge, on: info))
            }
            classes[info.name] = JVMClassInfo(name: info.name, flags: info.flags, superclass: superclass, interfaces: interfaces, methods: methods)
        }
    }
    func expose(_ type: JVMValueType) -> Bool {
        guard let name = type.referenceName else { return true }
        // Erased function interfaces require Kotlin function-type metadata;
        // their raw Java signatures are not importable declarations.
        if name.hasPrefix("kotlin/jvm/functions/Function") { return false }
        if name.hasPrefix("["), let element = try? JVMDescriptor.parse("()" + String(name.dropFirst())).1 { return expose(element) }
        return name == "java/lang/String" || name == "java/lang/Object" || classes[name] != nil
    }
    func kotlinType(_ type: JVMValueType) -> String {
        switch type {
        case .byte: return "kotlin.Byte"
        case .short: return "kotlin.Short"
        case .char: return "kotlin.Char"
        case .uint: return "kotlin.UInt"
        case .ulong: return "kotlin.ULong"
        case .ubyte: return "kotlin.UByte"
        case .ushort: return "kotlin.UShort"
        case let .unsignedArray(p, nullable): return "kotlin." + p.kotlinName + "Array" + (nullable ? "?" : "")
        case .int: return "kotlin.Int"
        case .long: return "kotlin.Long"
        case .float: return "kotlin.Float"
        case .double: return "kotlin.Double"
        case .boolean: return "kotlin.Boolean"
        case .unit: return "kotlin.Unit"
        case .string: return "kotlin.String"
        case let .reference(name, _, _):
            let base: String
            if name.hasPrefix("["), let element = try? JVMDescriptor.parse("()" + String(name.dropFirst())).1 {
                if let primitive = Self.primitiveArrays.first(where: { $0.value == element }) { return "kotlin." + primitive.key }
                return "kotlin.Array<" + kotlinType(element) + ">"
            }
            switch name {
            case "java/lang/String": return "kotlin.String"
            case "java/lang/Object": return "kotlin.Any"
            default: base = name.split(separator: "/").map { "`\($0)`" }.joined(separator: ".")
            }
            // Classfiles do not retain Kotlin nullability without metadata. Use
            // non-null source declarations as the current platform-type approximation.
            return base
        }
    }
    private func isSAM(_ name: String) -> Bool {
        var members: [String: JVMForeignMethod] = [:], visited: Set<String> = []
        func visit(_ name: String) {
            guard visited.insert(name).inserted, let info = classes[name] else { return }
            for parent in info.interfaces { visit(parent) }
            for method in info.methods where !method.isStatic && !method.isConstructor {
                if ["equals(Ljava/lang/Object;)Z", "hashCode()I", "toString()Ljava/lang/String;"].contains(method.name + method.descriptor) { continue }
                let key = method.name + method.descriptor.prefix(through: method.descriptor.firstIndex(of: ")")!)
                members[key] = method
            }
        }
        visit(name)
        return members.values.filter(\.isAbstract).count == 1
    }
    func inject(into ctx: CompilationContext) throws {
        let provided = try JVMStdlibCatalog.nominalNames(in: ctx)
        for info in classes.values.sorted(by: { $0.name < $1.name }) {
            // The frontend's Kotlin/JDK mapped declarations carry generic source
            // types. Importing the same erased class again would shadow them.
            if info.name.hasPrefix("kotlin/") || provided.contains(info.name) || Self.builtinName(info.name) != nil || ["kotlin/Unit", "kotlin/Function", "kotlin/Metadata"].contains(info.name) || info.name.hasPrefix("kotlin/jvm/functions/Function") { continue }
            let parts = info.name.split(separator: "/").map(String.init)
            guard let short = parts.last else { throw JVMClassReader.Invalid() }
            let package = parts.dropLast().map { "`\($0)`" }.joined(separator: ".")
            var source = package.isEmpty ? "" : "package \(package)\n"
            let own = info.methods.filter { $0.parameters.allSatisfy(expose) && expose($0.result) && ($0.isConstructor || JVMProgramBuilder.isIdentifier($0.name)) }
            let statics = own.filter(\.isStatic)
            let isFileFacade = short.hasSuffix("Kt")
            if isFileFacade {
                // The facade class itself stays importable: `import api.HelloKt`
                // resolves the nominal and `HelloKt.member(...)` reaches its
                // statics through the companion, matching Kotlin/JVM.
                source += "class `\(short)` private constructor() {\n"
                if !statics.isEmpty {
                    source += "companion object {\n"
                    for method in statics {
                        source += "external fun `\(method.name)`(" + parameters(method) + "): " + kotlinType(method.result) + "\n"
                    }
                    source += "}\n"
                }
                source += "}\n"
                for method in statics {
                    source += "external fun `\(method.name)`(" + parameters(method) + "): " + kotlinType(method.result) + "\n"
                    // A JVM file-facade descriptor does not distinguish a
                    // top-level function from an extension receiver. Expose
                    // the receiver form as well so Kotlin member syntax binds
                    // to the same static method.
                    if let receiver = method.parameters.first,
                       case .reference = receiver, receiver.referenceName?.hasPrefix("[") != true {
                        let rest = method.parameters.dropFirst().enumerated().map {
                            "p\($0.offset): " + kotlinType($0.element)
                        }.joined(separator: ", ")
                        source += "external fun \(kotlinType(receiver)).`\(method.name)`(\(rest)): \(kotlinType(method.result))\n"
                    }
                }
            } else {
                if info.isInterface { source += (isSAM(info.name) ? "fun interface `\(short)`" : "interface `\(short)`") }
                else {
                    source += info.flags & 0x0400 != 0 ? "abstract class " : (info.flags & 0x0010 != 0 ? "class " : "open class ")
                    source += "`\(short)` "
                    source += own.contains(where: { $0.isConstructor && $0.parameters.isEmpty }) ? "()" : "protected constructor()"
                }
                var parents: [String] = []
                if !info.isInterface, let base = info.superclass, classes[base] != nil {
                    parents.append(kotlinType(.reference(base, nullable: false)) + "()")
                }
                parents += info.interfaces.filter { classes[$0] != nil }.map { kotlinType(.reference($0, nullable: false)) }
                if !parents.isEmpty { source += " : " + parents.joined(separator: ", ") }
                source += " {\n"
                for method in own where method.isConstructor && !method.parameters.isEmpty {
                    source += "constructor(" + parameters(method) + ") : this() {}\n"
                }
                for method in own where !method.isConstructor && !method.isStatic {
                    let overrides = overridesParent(method, in: info, visited: [])
                    if !info.isInterface && method.isFinal { source += "final " }
                    source += overrides ? "override " : ""
                    if !info.isInterface { source += overrides || method.isFinal ? "" : "open " }
                    if method.name == "get", method.parameters.count == 1 { source += "operator " }
                    if !info.isInterface { source += "external " }
                    source += "fun `\(method.name)`(" + parameters(method) + "): " + kotlinType(method.result)
                    if info.isInterface, !method.isAbstract {
                        source += method.result == .unit ? " {}" : " = null!!"
                        // A default method with a primitive result still has a
                        // Nothing-typed stub body; it is never emitted or executed.
                    }
                    source += "\n"
                }
                for getter in own where !getter.isConstructor && !getter.isStatic && getter.parameters.isEmpty {
                    let propertyName: String
                    if getter.name.hasPrefix("get"), getter.name.count > 3 {
                        let suffix = String(getter.name.dropFirst(3))
                        propertyName = String(suffix.prefix(1)).lowercased() + suffix.dropFirst()
                    } else if getter.name.hasPrefix("is"), getter.name.count > 2, getter.result == .boolean {
                        propertyName = getter.name
                    } else { continue }
                    guard JVMProgramBuilder.isIdentifier(propertyName),
                          !own.contains(where: { !$0.isStatic && !$0.isConstructor && $0.name == propertyName }) else { continue }
                    if !info.isInterface && getter.isFinal { source += "final " }
                    if overridesParent(getter, in: info, visited: []) { source += "override " }
                    else if !info.isInterface && !getter.isFinal { source += "open " }
                    source += "val `\(propertyName)`: \(kotlinType(getter.result)) get() = `\(getter.name)`()\n"
                }
                if !statics.isEmpty {
                    source += "companion object {\n"
                    for method in statics {
                        source += "external fun `\(method.name)`(" + parameters(method) + "): " + kotlinType(method.result) + "\n"
                    }
                    source += "}\n"
                }
                source += "}\n"
            }
            let path = "<kswiftk-jvm-import>/" + info.name + ".kt"
            guard !ctx.sourceManager.containsFile(path: path) else { throw JVMClassReader.Invalid() }
            let file = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8), origin: .residualStdlib)
            sourceClasses[file] = info
        }
    }
    private func parameters(_ method: JVMForeignMethod) -> String {
        method.parameters.enumerated().map { "p\($0.offset): " + kotlinType($0.element) }.joined(separator: ", ")
    }
    private func overridesParent(_ method: JVMForeignMethod, in info: JVMClassInfo, visited: Set<String>) -> Bool {
        guard !visited.contains(info.name) else { return false }
        if ["toString()Ljava/lang/String;", "hashCode()I", "equals(Ljava/lang/Object;)Z"].contains(method.name + method.descriptor) { return true }
        let key = method.name + method.descriptor.prefix(through: method.descriptor.firstIndex(of: ")")!)
        for parentName in ([info.superclass].compactMap { $0 } + info.interfaces) {
            guard let parent = classes[parentName] else { continue }
            if parent.methods.contains(where: { !$0.isStatic && !$0.isConstructor && $0.name + $0.descriptor.prefix(through: $0.descriptor.firstIndex(of: ")")!) == key }) { return true }
            if overridesParent(method, in: parent, visited: visited.union([info.name])) { return true }
        }
        return false
    }
    /// Converts foreign reference signatures to Kotlin platform types after
    /// header collection and before any user body is checked.
    func bind(in ctx: CompilationContext, sema: SemaModule) throws {
        func platform(_ type: TypeID) -> TypeID {
            switch sema.types.kind(of: type) {
            case .classType, .stringStruct, .any, .typeParam: return sema.types.withNullability(.platformType, for: type)
            default: return type
            }
        }
        for symbol in sema.symbols.allSymbols() {
            guard let site = symbol.declSite, let info = sourceClasses[site.start.file],
                  symbol.kind == .function || symbol.kind == .constructor,
                  let signature = sema.symbols.functionSignature(for: symbol.id) else { continue }
            let name = symbol.kind == .constructor ? "<init>" : ctx.interner.resolve(symbol.name)
            let parent = sema.symbols.parentSymbol(for: symbol.id).flatMap(sema.symbols.symbol)
            let isTopLevel = parent?.kind == .package
            let isExtension = hasExtensionReceiver(symbol, in: ctx)
            if isExtension { extensionSymbols.insert(symbol.id) }
            let receiverTypes = isExtension ? signature.receiverType.map { [$0] } ?? [] : []
            let descriptorTypes = receiverTypes + signature.parameterTypes
            let descriptor = "(" + (try descriptorTypes.map { try Self.type($0, sema: sema, ctx: ctx).descriptor }).joined() + ")"
            let staticMember = isTopLevel || isExtension || (parent.map { ctx.interner.resolve($0.name) == "Companion" } ?? false)
            guard let method = info.methods.first(where: { $0.name == name && $0.descriptor.hasPrefix(descriptor) && $0.isStatic == staticMember }) else { continue }
            methods[symbol.id] = method
            let returnType = method.isConstructor ? signature.returnType : platform(signature.returnType)
            sema.symbols.setFunctionSignature(FunctionSignature(
                receiverType: signature.receiverType.map(platform),
                contextReceiverTypes: signature.contextReceiverTypes, contextParameterSymbols: signature.contextParameterSymbols,
                contextParameterTypes: signature.contextParameterTypes, parameterTypes: signature.parameterTypes.map(platform),
                returnType: returnType, isSuspend: signature.isSuspend, canThrow: false,
                valueParameterSymbols: signature.valueParameterSymbols,
                valueParameterUnsafeVarianceTypeParameterSymbols: signature.valueParameterUnsafeVarianceTypeParameterSymbols,
                valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                valueParameterIsVararg: signature.valueParameterIsVararg,
                valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn,
                hasExplicitInlineParameterMetadata: signature.hasExplicitInlineParameterMetadata,
                typeParameterSymbols: signature.typeParameterSymbols, reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
                typeParameterUpperBoundsList: signature.typeParameterUpperBoundsList, classTypeParameterCount: signature.classTypeParameterCount
            ), for: symbol.id)
        }
        for symbol in sema.symbols.allSymbols() where symbol.kind == .function {
            guard let parent = sema.symbols.parentSymbol(for: symbol.id).flatMap(sema.symbols.symbol),
                  parent.fqName.map(ctx.interner.resolve) == ["kotlin", "Any"],
                  let signature = sema.symbols.functionSignature(for: symbol.id) else { continue }
            let name = ctx.interner.resolve(symbol.name)
            guard ["toString", "hashCode", "equals"].contains(name) else { continue }
            let parameters = try signature.parameterTypes.map { try Self.type($0, sema: sema, ctx: ctx) }
            let result = try Self.type(signature.returnType, sema: sema, ctx: ctx)
            let descriptor = "(" + parameters.map(\.descriptor).joined() + ")" + result.descriptor
            methods[symbol.id] = JVMForeignMethod(owner: "java/lang/Object", name: name, descriptor: descriptor, parameters: parameters, result: result, isStatic: false, isInterface: false, isAbstract: false)
        }
    }
    private func hasExtensionReceiver(_ symbol: SemanticSymbol, in ctx: CompilationContext) -> Bool {
        guard let site = symbol.declSite, let ast = ctx.ast,
              let file = ast.files.first(where: { $0.fileID == site.start.file }) else { return false }
        for declaration in file.topLevelDecls {
            guard case let .funDecl(function) = ast.arena.decl(declaration), function.range == site else { continue }
            return function.receiverType != nil
        }
        return false
    }
    static func type(_ id: TypeID, sema: SemaModule, ctx: CompilationContext) throws -> JVMValueType {
        switch sema.types.kind(of: id) {
        case let .intersection(parts):
            let concrete = parts.first { part in
                switch sema.types.kind(of: part) { case .primitive, .stringStruct: return true; case let .classType(t): return sema.symbols.symbol(t.classSymbol)?.kind != .interface; default: return false }
            } ?? parts.first { part in
                switch sema.types.kind(of: part) { case .typeParam, .any: return false; default: return true }
            } ?? parts.first
            guard let concrete else { throw JVMFrontendError(message: "Empty JVM intersection type.") }
            return try Self.type(concrete, sema: sema, ctx: ctx)
        case let .kClassType(t): return .reference("kotlin/reflect/KClass", nullable: t.nullability != .nonNull)
        case .unit: return .unit
        case .nothing(.nonNull): return .reference("java/lang/Void", nullable: false)
        case .nullableUnit: return .reference("kotlin/Unit", nullable: true)
        case .nothing(.nullable): return .reference("java/lang/Object", nullable: true)
        case let .any(nullability): return .reference("java/lang/Object", nullable: nullability != .nonNull, platform: nullability == .platformType)
        case let .stringStruct(nullability): return nullability == .nonNull ? .string : .reference("java/lang/String", nullable: true, platform: nullability == .platformType)
        case let .functionType(function):
            guard !function.params.contains(where: { if case .unit = sema.types.kind(of: $0) { return true }; return false }), function.contextReceivers.isEmpty, function.params.count + (function.receiver == nil ? 0 : 1) + (function.isSuspend ? 1 : 0) <= 22 else { throw JVMFrontendError(message: "JVM M7 supports Function0 through Function22, including a suspend continuation, without context receivers or Unit parameters.") }
            return .reference("kotlin/jvm/functions/Function" + String(function.params.count + (function.receiver == nil ? 0 : 1) + (function.isSuspend ? 1 : 0)), nullable: function.nullability != .nonNull)
        case let .typeParam(parameter):
            if let bound = sema.symbols.typeParameterUpperBound(for: parameter.symbol) {
                if case let .typeParam(other) = sema.types.kind(of: bound), other.symbol == parameter.symbol { return .reference("java/lang/Object", nullable: true) }
                let upper = try Self.type(bound, sema: sema, ctx: ctx)
                // Final primitive bounds use primitive JVM descriptors. A
                // nullable use or nullable bound still requires its wrapper.
                let erased = parameter.nullability == .nonNull && (upper.isNumeric || upper == .boolean)
                    ? upper : boxed(upper)
                if parameter.nullability == .nullable, let name = erased.referenceName { return .reference(name, nullable: true) }
                return erased
            }
            return .reference("java/lang/Object", nullable: true)
        case let .primitive(p, n) where n != .nonNull:
            if let name = JVMValueType.primitive(p).unsignedName { return .reference(name, nullable: true) }
            guard let wrapper = wrappers[p.kotlinName] else { throw JVMFrontendError(message: "Unsupported boxed JVM primitive.") }
            return .reference("java/lang/" + wrapper, nullable: true, platform: n == .platformType)
        case let .classType(type):
            guard let symbol = sema.symbols.symbol(type.classSymbol) else { throw JVMClassReader.Invalid() }
            let name = Self.binaryName(symbol.id, sema: sema, ctx: ctx)
            if symbol.kind == .object,
               let site = symbol.declSite, ctx.sourceManager.origin(of: site.start.file) == .residualStdlib,
               let parent = sema.symbols.parentSymbol(for: symbol.id).flatMap(sema.symbols.symbol), parent.kind == .class,
               name.hasSuffix("$Companion") {
                let outer = String(name.dropLast("$Companion".count))
                if ctx.jvmImports?.classes[outer] != nil {
                    return .reference(outer, nullable: type.nullability != .nonNull)
                }
            }
            if name == "kotlin/Array" {
                guard let arg = type.args.first else { throw JVMFrontendError(message: "JVM Array needs an element type.") }
                let element = try argumentType(arg, sema: sema, ctx: ctx)
                let descriptor = "[" + element.descriptor
                guard descriptor.prefix(while: { $0 == "[" }).count <= 255 else { throw JVMFrontendError(message: "JVM arrays support at most 255 dimensions.") }
                return .reference(descriptor, nullable: type.nullability != .nonNull)
            }
            if ctx.jvmRuntimeClassAliases[symbol.fqName.map(ctx.interner.resolve).joined(separator: "/")] == nil, name.hasPrefix("kotlin/"), let p = [PrimitiveType.uint, .ulong, .ubyte, .ushort].first(where: { name == "kotlin/" + $0.kotlinName + "Array" }) { return .unsignedArray(p, nullable: type.nullability != .nonNull) }
            if let element = primitiveArrays[String(name.dropFirst(7))], name.hasPrefix("kotlin/") { return .reference("[" + element.descriptor, nullable: type.nullability != .nonNull) }
            // Result's non-null logical value may carry a successful null.
            if name == "kotlin/Result" { return ctx.options.stdlibOnly ? .reference(name, nullable: type.nullability != .nonNull) : .reference("java/lang/Object", nullable: true) }
            if let mapped = builtinName(name) { return .reference(mapped, nullable: type.nullability != .nonNull) }
            guard ctx.jvmImports?.classes[name] != nil || symbol.declSite.map({ ctx.sourceManager.origin(of: $0.start.file) == .user && (symbol.kind == .class || symbol.kind == .interface || symbol.kind == .object || symbol.kind == .enumClass || symbol.kind == .annotationClass) }) == true else {
                let owner = symbol.fqName.map(ctx.interner.resolve).joined(separator: ".")
                throw JVMFrontendError(message: "Unsupported JVM reference type: \(name) used by \(owner)")
            }
            return .reference(name, nullable: type.nullability != .nonNull, platform: type.nullability == .platformType)
        case let .primitive(p, .nonNull):
            return .primitive(p)
        default: break
        }
        throw JVMFrontendError(message: "Unsupported JVM value type: \(sema.types.kind(of: id))")
    }
}

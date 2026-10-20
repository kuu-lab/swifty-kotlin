import Foundation
import CompilerCore

/// Kotlin metadata 2.0 file facades and classes for the JVM subset.
/// Field numbers follow Kotlin's metadata.proto, jvm_metadata.proto and
/// jvm_module.proto. Explicit JVM signatures avoid inferred ABI mappings.
enum JVMMetadata {
    struct Proto {
        var bytes = Data()
        mutating func varint(_ raw: Int) {
            var value = raw
            while value >= 128 { bytes.append(UInt8(value & 127) | 128); value >>= 7 }
            bytes.append(UInt8(value))
        }
        mutating func int(_ field: Int, _ value: Int) { varint(field << 3); varint(value) }
        mutating func data(_ field: Int, _ value: Data) {
            varint(field << 3 | 2); varint(value.count); bytes.append(value)
        }
        mutating func string(_ field: Int, _ value: String) { data(field, Data(value.utf8)) }
    }
    static func annotation(_ program: JVMProgram, type declaration: JVMClass? = nil, pool: JVMConstantPool) throws -> Data {
        func metadataName(_ name: String) -> String { name.replacingOccurrences(of: "$", with: ".") }
        var strings: [String] = []
        func index(_ string: String) -> Int {
            if let i = strings.firstIndex(where: { $0.utf16.elementsEqual(string.utf16) }) { return i }
            strings.append(string); return strings.count - 1
        }
        func type(_ type: JVMValueType) -> Data {
            let name: String
            switch type {
            case .byte: name = "kotlin/Byte"
            case .short: name = "kotlin/Short"
            case .char: name = "kotlin/Char"
            case .uint, .ulong, .ubyte, .ushort, .unsignedArray: name = type.unsignedName!
            case .int: name = "kotlin/Int"
            case .long: name = "kotlin/Long"
            case .float: name = "kotlin/Float"
            case .double: name = "kotlin/Double"
            case .boolean: name = "kotlin/Boolean"
            case .string: name = "kotlin/String"
            case .unit: name = "kotlin/Unit"
            case let .reference(ref, _, _):
                name = ref == "java/lang/String" ? "kotlin/String" : (ref == "java/lang/Object" ? "kotlin/Any" : ref)
            }
            var proto = Proto(); proto.int(6, index(name))
            if type.isPlatform {
                proto.int(4, index("kotlin.jvm.PlatformType"))
                var upper = Proto(); upper.int(6, index(name)); upper.int(3, 1)
                proto.data(5, upper.bytes)
            } else if type.isNullable { proto.int(3, 1) }
            return proto.bytes
        }
        func sourceType(_ t: JVMKotlinType) -> Data {
            var p = Proto()
            switch t {
            case let .function(parameters, result, receiver, nullable, suspend):
                let inputs = [receiver].compactMap { $0 } + parameters
                if suspend {
                    // Kotlin metadata records the lowered FunctionN shape and
                    // marks it as suspend so foreign reflection restores R.
                    let continuation = JVMKotlinType.named("kotlin/coroutines/Continuation", [JVMKotlinTypeArgument(type: result, variance: 2)], nullable: false)
                    let runtime = inputs + [continuation, .named("kotlin/Any", [], nullable: true)]
                    p.bytes = sourceType(.named("kotlin/Function" + String(inputs.count + 1), runtime.map { JVMKotlinTypeArgument(type: $0, variance: 2) }, nullable: nullable))
                    p.int(1, 1)
                } else {
                    p.bytes = sourceType(.named("kotlin/Function" + String(inputs.count), (inputs + [result]).map { JVMKotlinTypeArgument(type: $0, variance: 2) }, nullable: nullable))
                }
                if receiver != nil { var annotation = Proto(); annotation.int(1, index("kotlin/ExtensionFunctionType")); p.data(100, annotation.bytes) }
            case let .flexible(lower, upper):
                p.bytes = sourceType(lower); p.int(4, index("kotlin.jvm.PlatformType")); p.data(5, sourceType(upper))
            case let .parameter(id, nullable):
                p.int(7, id)
                if nullable { p.int(3, 1) }
            case let .named(name, arguments, nullable):
                p.int(6, index(metadataName(name)))
                if nullable { p.int(3, 1) }
                for argument in arguments {
                    var a = Proto(); a.int(1, argument.variance)
                    if let type = argument.type { a.data(2, sourceType(type)) }
                    p.data(2, a.bytes)
                }
            }
            return p.bytes
        }
        func typeParameter(_ parameter: JVMTypeParameter) -> Data {
            var p = Proto(); p.int(1, parameter.id); p.int(2, index(parameter.name)); if parameter.isReified { p.int(3, 1) }; p.int(4, parameter.variance)
            for bound in parameter.bounds { p.data(5, sourceType(bound)) }
            return p.bytes
        }
        func visibility(_ modifiers: Modifiers) -> Int {
            modifiers.contains(.private) ? 2 : (modifiers.contains(.protected) ? 4 : (modifiers.contains(.internal) ? 0 : 6))
        }
        func functionFlags(_ function: JVMFunction) -> Int {
            let visible = function.isPrivate ? 2 : (function.isInternal ? 0 : ((function.access ?? 0) & 4 != 0 ? 4 : 6))
            let modality = function.isAbstract ? 32 : (function.access.map { $0 & 16 == 0 ? 16 : 0 } ?? 0)
            return (function.annotations.isEmpty ? 0 : 1) | visible | modality | (function.isOperator ? 256 : 0) | (function.isInfix ? 512 : 0) | (function.isInline ? 1024 : 0) | (function.isSuspend ? 8192 : 0)
        }
        func signature(_ name: String, _ descriptor: String) -> Data {
            var proto = Proto(); proto.int(1, index(name)); proto.int(2, index(descriptor)); return proto.bytes
        }
        func parameter(_ name: String, _ parameterType: JVMValueType, _ source: JVMKotlinType? = nil, flags: Int = 0, vararg: JVMKotlinType? = nil) -> Data {
            var proto = Proto(); if flags != 0 { proto.int(1, flags) }; proto.int(2, index(name)); proto.data(3, source.map(sourceType) ?? type(parameterType)); if let vararg { proto.data(4, sourceType(vararg)) }; return proto.bytes
        }
        func function(_ function: JVMFunction) -> Data {
            let ref = function.reference
            var proto = Proto(); proto.int(9, functionFlags(function))
            if let receiver = function.kotlinReceiver { proto.data(5, sourceType(receiver)) }
            proto.int(2, index(function.sourceName ?? ref.name)); proto.data(3, function.kotlinResult.map(sourceType) ?? type(ref.result))
            for t in function.typeParameters { proto.data(4, typeParameter(t)) }
            for (i, pair) in zip(function.parameterNames, Array(ref.parameters.dropFirst(function.metadataParameterOffset + (function.kotlinReceiver == nil ? 0 : 1)))).enumerated() { proto.data(6, parameter(pair.0, pair.1, function.kotlinParameters.indices.contains(i) ? function.kotlinParameters[i] : nil, flags: (function.parameterInlineFlags.indices.contains(i) ? function.parameterInlineFlags[i] : 0) | (function.parameterDefaultFlags.indices.contains(i) && function.parameterDefaultFlags[i] ? 2 : 0) | (function.parameterAnnotations.indices.contains(i + function.metadataParameterOffset + (function.kotlinReceiver == nil ? 0 : 1)) && !function.parameterAnnotations[i + function.metadataParameterOffset + (function.kotlinReceiver == nil ? 0 : 1)].isEmpty ? 1 : 0), vararg: function.parameterVarargTypes.indices.contains(i) ? function.parameterVarargTypes[i] : nil)) }
            proto.data(100, signature(ref.name, ref.descriptor)); return proto.bytes
        }
        func propertyMetadata(_ property: JVMProperty, functions: [JVMFunction]) -> Data {
            let getter = functions.first { $0.reference.name == property.getter.name && $0.reference.descriptor == property.getter.descriptor }
            let setter = property.setter.flatMap { method in functions.first { $0.reference.name == method.name && $0.reference.descriptor == method.descriptor } }
            var proto = Proto()
            let flags = visibility(property.modifiers) | (getter?.isAbstract == true ? 32 : ((getter?.access ?? 0) & 16 == 0 ? 16 : 0))
            proto.int(11, flags | (property.modifiers.contains(.const) ? 2048 | 8192 : 0) | (property.annotationsMethod == nil ? 0 : 1) | 512 | (setter == nil ? 0 : 256 | 1024) | (property.modifiers.contains(.lateinit) ? 4096 : 0) | (property.delegateSymbol != nil ? 32768 : 0))
            proto.int(2, index(property.name)); proto.data(3, property.kotlinType.map(sourceType) ?? type(property.type))
            if !property.modifiers.contains(.const), let getter { proto.int(7, functionFlags(getter) | (property.customGetter ? 64 : 0)) }
            if let setter {
                proto.int(8, functionFlags(setter) | (property.customSetter ? 64 : 0))
                proto.data(6, parameter(setter.parameterNames.first ?? "value", property.type, property.kotlinType))
            }
            var jvm = Proto()
            if let field = property.delegateField ?? property.field { jvm.data(1, signature(field.name, field.type.descriptor)) }
            if let carrier = property.annotationsMethod { jvm.data(2, signature(carrier.name, carrier.descriptor)) }
            if !property.modifiers.contains(.const) { jvm.data(3, signature(property.getter.name, property.getter.descriptor)) }
            if let method = property.setter { jvm.data(4, signature(method.name, method.descriptor)) }
            proto.data(100, jvm.bytes); return proto.bytes
        }
        func typeAlias(_ alias: JVMTypeAlias) -> Data {
            var p = Proto(); p.int(1, visibility(alias.modifiers)); p.int(2, index(alias.name))
            for t in alias.typeParameters { p.data(3, typeParameter(t)) }
            p.data(4, sourceType(alias.underlyingType)); p.data(6, sourceType(alias.underlyingType))
            return p.bytes
        }
        var package = Proto()
        if let declaration {
            let modality = declaration.isSealed ? 48 : (declaration.isInterface || declaration.access & 0x0400 != 0 ? 32 : (declaration.access & 16 == 0 ? 16 : 0))
            package.int(1, visibility(declaration.modifiers) | modality | (declaration.annotations.isEmpty ? 0 : 1) | (declaration.isValue ? 8192 : 0) | (declaration.isFunInterface ? 16384 : 0) | (declaration.isData ? 1024 : 0) | (declaration.isInner ? 512 : 0) | (declaration.isCompanion ? 384 : (declaration.isObject ? 320 : (declaration.isEnum ? 128 : (declaration.isAnnotation ? 256 : (declaration.isInterface ? 64 : 0))))))
            package.int(3, index(metadataName(declaration.name)))
            if let underlying = declaration.underlyingProperty { package.int(17, index(underlying)) }
            for alias in declaration.typeAliases { package.data(11, typeAlias(alias)) }
            if let companion = declaration.companionName { package.int(4, index(companion)) }
            for nested in declaration.nestedNames { package.int(7, index(nested)) }
            for subclass in declaration.sealedSubclasses { package.int(16, index(metadataName(subclass))) }
            for entry in declaration.enumEntries { var value = Proto(); value.int(1, index(entry)); package.data(13, value.bytes) }
            for t in declaration.typeParameters { package.data(5, typeParameter(t)) }
            if !declaration.kotlinSupertypes.isEmpty { for t in declaration.kotlinSupertypes { package.data(6, sourceType(t)) } }
            else { for parent in [declaration.superclass] + declaration.interfaces { package.data(6, type(.reference(parent, nullable: false))) } }
            let accessorNames = Set(declaration.properties.flatMap { [$0.getter.name + $0.getter.descriptor] + ($0.setter.map { [$0.name + $0.descriptor] } ?? []) })
            for member in declaration.functions + [declaration.annotationConstructor].compactMap({ $0 }) where (member.access ?? 0) & 0x1000 == 0 && member.reference.name != "<clinit>" {
                if member.isConstructor || member.isValueConstructor {
                    if member.isSynthetic { continue }
                    var proto = Proto()
                    proto.int(1, (member.annotations.isEmpty ? 0 : 1) | (member.isPrivate ? 2 : (member.isInternal ? 0 : ((member.access ?? 0) & 4 != 0 ? 4 : 6))) | (member.isSecondaryConstructor ? 16 : 0))
                    for (i, pair) in zip(member.parameterNames, Array(member.reference.parameters.dropFirst(member.kotlinParameterOffset))).enumerated() { proto.data(2, parameter(pair.0, pair.1, member.kotlinParameters.indices.contains(i) ? member.kotlinParameters[i] : nil, flags: (member.parameterDefaultFlags.indices.contains(i) && member.parameterDefaultFlags[i] ? 2 : 0) | (member.parameterAnnotations.indices.contains(i + member.kotlinParameterOffset) && !member.parameterAnnotations[i + member.kotlinParameterOffset].isEmpty ? 1 : 0), vararg: member.parameterVarargTypes.indices.contains(i) ? member.parameterVarargTypes[i] : nil)) }
                    proto.data(100, signature(member.isValueConstructor ? "constructor-impl" : "<init>", member.metadataDescriptor ?? member.reference.descriptor)); package.data(8, proto.bytes)
                } else if !accessorNames.contains(member.reference.name + member.reference.descriptor) { package.data(9, function(member)) }
            }
            for property in declaration.properties { package.data(10, propertyMetadata(property, functions: declaration.functions)) }
            package.int(101, index(program.moduleName))
            if declaration.isInterface { package.int(104, 1) }
        } else {
            for alias in program.typeAliases { package.data(5, typeAlias(alias)) }
            let accessors = Set(program.properties.flatMap { [$0.getter.name + $0.getter.descriptor] + ($0.setter.map { [$0.name + $0.descriptor] } ?? []) })
            for member in program.functions where !member.isSynthetic && member.reference.name != "<clinit>" && !accessors.contains(member.reference.name + member.reference.descriptor) { package.data(3, function(member)) }
            for property in program.properties { package.data(4, propertyMetadata(property, functions: program.functions)) }
            package.int(101, index(program.moduleName))
        }
        var record = Proto(); record.int(1, strings.count)
        var table = Proto(); table.data(1, record.bytes)
        var wire = Proto(); wire.varint(table.bytes.count); wire.bytes.append(table.bytes); wire.bytes.append(package.bytes)
        // BitEncoding's UTF8 mode: the NUL marker is followed by one UTF-16
        // code unit per raw byte, then encoded as classfile modified UTF-8.
        let units = [UInt16(0)] + wire.bytes.map(UInt16.init)
        let chunks = stride(from: 0, to: units.count, by: 30_000).map {
            String(decoding: units[$0..<min($0 + 30_000, units.count)], as: UTF16.self)
        }
        guard strings.count <= 65_535, chunks.count <= 65_535 else { throw JVMEmissionError.limit("Kotlin metadata exceeds annotation array limits.") }
        var bytes = JVMBytes(); bytes.u2(1); bytes.u2(try pool.utf8("Lkotlin/Metadata;")); bytes.u2(6)
        func int(_ value: Int) throws {
            bytes.u1(73); bytes.u2(try pool.constant(.int(Int32(value))))
        }
        func namedInt(_ name: String, _ value: Int) throws {
            bytes.u2(try pool.utf8(name)); try int(value)
        }
        func array(_ name: String, _ values: [String]) throws {
            bytes.u2(try pool.utf8(name)); bytes.u1(91); bytes.u2(UInt16(values.count))
            for value in values { bytes.u1(115); bytes.u2(try pool.utf8(value)) }
        }
        try namedInt("k", declaration == nil ? 2 : 1)
        bytes.u2(try pool.utf8("mv")); bytes.u1(91); bytes.u2(3)
        for number in [2, 0, 0] { try int(number) }
        try namedInt("xi", 48)
        try array("d1", chunks); try array("d2", strings)
        // pn is optional, but explicit package names also describe root facades.
        bytes.u2(try pool.utf8("pn")); bytes.u1(115)
        bytes.u2(try pool.utf8((declaration?.name ?? program.internalClassName).split(separator: "/").dropLast().joined(separator: ".")))
        return bytes.data
    }
    static func module(_ program: JVMProgram) -> Data {
        let facades = [program.internalClassName] + program.classes.filter(\.isFileFacade).map(\.name)
        let packages = Dictionary(grouping: facades) { $0.split(separator: "/").dropLast().joined(separator: ".") }
        var module = Proto()
        for name in packages.keys.sorted() {
            var package = Proto(); package.string(1, name)
            for facade in packages[name]!.sorted() { package.string(2, String(facade.split(separator: "/").last!)) }
            module.data(1, package.bytes)
        }
        var bytes = JVMBytes()
        for value: UInt32 in [3, 2, 0, 0, 0] { bytes.u4(value) }
        bytes.data.append(module.bytes); return bytes.data
    }
}

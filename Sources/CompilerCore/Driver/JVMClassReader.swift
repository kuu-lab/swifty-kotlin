import Foundation

struct JVMClassInfo {
    let name: String
    let flags: UInt16
    let superclass: String?
    let interfaces: [String]
    var methods: [JVMForeignMethod]
    var fields: [JVMForeignField] = []
    var bridgeMethods: [JVMForeignMethod] = []
    var defaultArgumentMethods: [JVMForeignMethod] = []
    var metroAccessors: [JVMForeignMethod] = []
    var classTypeParameterNames: [String] = []
    var kotlinTypeParameterVariance: [String: String] = [:]
    var genericSignature: String?
    var innerClasses: [JVMInnerClassInfo] = []
    var hasInnerClassesAttribute = false
    var hasEnclosingMethod = false
    var isKotlinFileFacade: Bool?
    var kotlinSealedInterfaceSubclasses: [String] = []
    var isKotlinObject = false
    var kotlinReadOnlyCollectionSupertypes: [String: String] = [:]
    var kotlinComparableSupertype: String?
    var kotlinParameterizedSupertypes: [String: [String]] = [:]
    var kotlinLoweredConstructors: [(source: JVMKotlinValueConstructor, entry: JVMForeignMethod, defaults: JVMForeignMethod?)] = []
    var kotlinValueClassConstructors: [(source: JVMKotlinValueConstructor, adapter: JVMForeignMethod)] = []
    var annotations: [JVMAnnotation] = []
    var kotlinStaticProperties: [String: (getter: JVMForeignMethod, isNullable: Bool)] = [:]
    var kotlinMemberProperties: [String: (getter: JVMForeignMethod, sourceType: String)] = [:]
    var kotlinTopLevelConstants: [String: String] = [:]
    var kotlinTopLevelProperties: [(source: JVMKotlinTopLevelProperty, getter: JVMForeignMethod)] = []
    var kotlinMultifileParts: [String] = []
    var isKotlinMultifilePart = false
    var isInterface: Bool { flags & 0x0200 != 0 }
    var isAnnotation: Bool { flags & 0x2000 != 0 }
    var repeatableAnnotationContainer: String? {
        guard isAnnotation,
              let repeatable = annotations.first(where: { $0.descriptor == "Ljava/lang/annotation/Repeatable;" }),
              case let .classType(container)? = repeatable.values.first(where: { $0.0 == "value" })?.1,
              container.hasPrefix("L"), container.hasSuffix(";") else { return nil }
        return String(container.dropFirst().dropLast())
    }

    func isRuntimeStaticField(_ field: JVMForeignField) -> Bool {
        isKotlinFileFacade == nil && field.isPublic && field.isStatic
            && (!field.isFinal || field.constantValue == nil) && field.access & 0x5000 == 0
    }

    func isRuntimeInstanceField(_ field: JVMForeignField) -> Bool {
        isKotlinFileFacade == nil && field.isPublic && !field.isStatic && field.access & 0x1000 == 0
    }
}

struct JVMInnerClassInfo {
    let name: String
    let outerName: String?
    let innerName: String?
    let access: UInt16
}

struct JVMForeignField {
    let name: String
    let descriptor: String
    let access: UInt16
    /// `ConstantValue` attribute payload for `static final` fields, when the
    /// classfile carries one. Used to emit Kotlin `const`-style literals.
    var constantValue: JVMFieldConstant?
    var isStatic: Bool { access & 8 != 0 }
    var isPublic: Bool { access & 1 != 0 }
    var isFinal: Bool { access & 16 != 0 }
}

/// A `ConstantValue` field attribute resolved through the constant pool.
enum JVMFieldConstant {
    case int(Int32), long(Int64), float(Float), double(Double), string(String)
}

/// Reads declarations only. Dependency code and class initializers are never run.
struct JVMClassReader {
    var bytes: [UInt8]
    var offset = 0
    var strings: [Int: String] = [:]
    var classes: [Int: Int] = [:]
    var constants: [Int: JVMFieldConstant] = [:]
    struct Invalid: Error {}

    mutating func u1() throws -> UInt8 {
        guard offset < bytes.count else { throw Invalid() }
        defer { offset += 1 }; return bytes[offset]
    }
    mutating func u2() throws -> UInt16 { let a = try u1(); return UInt16(a) << 8 | UInt16(try u1()) }
    mutating func u4() throws -> UInt32 { let a = try u2(); return UInt32(a) << 16 | UInt32(try u2()) }
    mutating func skip(_ n: Int) throws {
        guard n >= 0, n <= bytes.count - offset else { throw Invalid() }; offset += n
    }
    func text(_ index: Int) throws -> String { guard let s = strings[index] else { throw Invalid() }; return s }
    func className(_ index: Int) throws -> String { guard let s = classes[index] else { throw Invalid() }; return try text(s) }

    /// Import a single result type parameter and any Class<T> parameters
    /// sharing it. Other parameter types must match their erased descriptors.
    private static func genericResultParameter(
        in signature: String?, method: JVMForeignMethod
    ) -> (name: String, classParameterIndices: Set<Int>)? {
        guard let signature, signature.first == "<", let colon = signature.firstIndex(of: ":"),
              method.result.referenceName != nil, !method.isConstructor else { return nil }
        let name = String(signature[signature.index(after: signature.startIndex)..<colon])
        guard JVMProgramBuilder.isIdentifier(name) else { return nil }
        let bound = method.result.descriptor
        let classType = "Ljava/lang/Class<T\(name);>;"
        for separator in [":", "::"] {
            let prefix = "<\(name)\(separator)\(bound)>("
            guard signature.hasPrefix(prefix) else { continue }
            var remaining = signature.dropFirst(prefix.count)
            var classParameters: Set<Int> = []
            for (index, parameter) in method.parameters.enumerated() {
                if parameter.referenceName == "java/lang/Class", remaining.hasPrefix(classType) {
                    classParameters.insert(index)
                    remaining = remaining.dropFirst(classType.count)
                } else if remaining.hasPrefix(parameter.descriptor) {
                    remaining = remaining.dropFirst(parameter.descriptor.count)
                } else {
                    return nil
                }
            }
            let suffix = ")T\(name);"
            if remaining == suffix || remaining.hasPrefix(suffix + "^") { return (name, classParameters) }
        }
        return nil
    }
    /// Field attributes: returns the resolved `ConstantValue` payload, if any.
    mutating func fieldAttributes() throws -> JVMFieldConstant? {
        var result: JVMFieldConstant?
        let count = try u2()
        for _ in 0..<count {
            let nameIndex = Int(try u2())
            let size = try u4()
            let end = offset + Int(size)
            if try text(nameIndex) == "ConstantValue", size == 2 {
                result = constants[Int(try u2())]
            } else {
                try skip(Int(size))
            }
            guard offset == end else { throw Invalid() }
        }
        return result
    }
    /// Method attributes: the generic signature, annotation-class element
    /// defaults, and annotations carried by those element declarations. Other
    /// attributes keep the declaration-only skipping behavior.
    private struct MethodAttributes {
        var signature: String?
        var annotations: [JVMAnnotation] = []
        var annotationDefault: JVMAnnotationValue?
        var parameterAnnotations: [[JVMAnnotation]] = []
    }

    private mutating func methodAttributes(parseAnnotations: Bool, parseParameters: Bool) throws -> MethodAttributes {
        var attributes = MethodAttributes()
        let count = try u2()
        for _ in 0..<count {
            let nameIndex = Int(try u2())
            let size = try u4()
            let end = offset + Int(size)
            let attributeName = try text(nameIndex)
            if attributeName == "Signature" {
                guard attributes.signature == nil, size == 2 else { throw Invalid() }
                attributes.signature = try text(Int(u2()))
            } else if parseAnnotations, attributeName == "AnnotationDefault" {
                attributes.annotationDefault = try readAnnotationValue(tag: u1())
            } else if parseAnnotations, attributeName == "RuntimeVisibleAnnotations" {
                attributes.annotations += try readAnnotations(visible: true)
            } else if parseAnnotations, attributeName == "RuntimeInvisibleAnnotations" {
                attributes.annotations += try readAnnotations(visible: false)
            } else if parseParameters,
                      attributeName == "RuntimeVisibleParameterAnnotations" || attributeName == "RuntimeInvisibleParameterAnnotations" {
                let parameterCount = Int(try u1())
                let visible = attributeName == "RuntimeVisibleParameterAnnotations"
                for index in 0..<parameterCount {
                    let annotations = try readAnnotations(visible: visible)
                    if index == attributes.parameterAnnotations.count { attributes.parameterAnnotations.append(annotations) }
                    else { attributes.parameterAnnotations[index] += annotations }
                }
            } else {
                try skip(Int(size))
            }
            guard offset == end else { throw Invalid() }
        }
        return attributes
    }
    private mutating func classAttributes(hasKotlinMetadata: Bool, parseAnnotations: Bool) throws -> (
        signature: String?, innerClasses: [JVMInnerClassInfo], hasInnerClassesAttribute: Bool,
        hasEnclosingMethod: Bool, kotlinMetadata: JVMKotlinMetadata?, annotations: [JVMAnnotation]
    ) {
        let count = try u2()
        var signature: String?
        var innerClasses: [JVMInnerClassInfo] = []
        var hasInnerClassesAttribute = false
        var hasEnclosingMethod = false
        var kotlinMetadata: JVMKotlinMetadata?
        var annotations: [JVMAnnotation] = []
        for _ in 0..<count {
            let attributeName = try text(Int(u2()))
            let size = try u4()
            guard size <= UInt32(bytes.count - offset) else { throw Invalid() }
            let end = offset + Int(size)
            switch attributeName {
            case "Signature":
                guard signature == nil, size == 2 else { throw Invalid() }
                signature = try text(Int(u2()))
            case "InnerClasses":
                guard !hasInnerClassesAttribute, size >= 2 else { throw Invalid() }
                hasInnerClassesAttribute = true
                let entryCount = Int(try u2())
                guard size == UInt32(2 + entryCount * 8) else { throw Invalid() }
                for _ in 0..<entryCount {
                    let innerIndex = Int(try u2())
                    let outerIndex = Int(try u2())
                    let innerNameIndex = Int(try u2())
                    let access = try u2()
                    innerClasses.append(JVMInnerClassInfo(
                        name: try className(innerIndex),
                        outerName: outerIndex == 0 ? nil : try className(outerIndex),
                        innerName: innerNameIndex == 0 ? nil : try text(innerNameIndex),
                        access: access
                    ))
                }
            case "EnclosingMethod":
                guard !hasEnclosingMethod, size == 4 else { throw Invalid() }
                hasEnclosingMethod = true
                try skip(Int(size))
            case "RuntimeVisibleAnnotations", "RuntimeInvisibleAnnotations":
                let visible = attributeName == "RuntimeVisibleAnnotations"
                if hasKotlinMetadata, kotlinMetadata == nil {
                    var annotationReader = JVMClassReader(bytes: Array(bytes[offset..<end]), strings: strings, constants: constants)
                    kotlinMetadata = try? annotationReader.readKotlinMetadata()
                }
                if parseAnnotations {
                    var annotationReader = JVMClassReader(bytes: Array(bytes[offset..<end]), strings: strings, constants: constants)
                    annotations += (try? annotationReader.readAnnotations(visible: visible)) ?? []
                }
                offset = end
            default:
                try skip(Int(size))
            }
            guard offset == end else { throw Invalid() }
        }
        return (signature, innerClasses, hasInnerClassesAttribute, hasEnclosingMethod, kotlinMetadata, annotations)
    }

    private mutating func readKotlinMetadata() throws -> JVMKotlinMetadata? {
        let count = try u2()
        for _ in 0..<count {
            let descriptor = try text(Int(u2()))
            let elementCount = try u2()
            if descriptor != "Lkotlin/Metadata;" {
                for _ in 0..<elementCount {
                    try skip(2)
                    try skipAnnotationValue(tag: u1())
                }
                continue
            }
            var metadata = JVMKotlinMetadata()
            for _ in 0..<elementCount {
                let name = try text(Int(u2()))
                let tag = try u1()
                switch (name, tag) {
                case ("k", 73):
                    metadata.kind = try annotationInt()
                case ("mv", 91):
                    let length = try u2()
                    metadata.version = try (0..<length).map { _ in
                        guard try u1() == 73 else { throw Invalid() }
                        return try annotationInt()
                    }
                case ("d1", 91), ("d2", 91):
                    let length = try u2()
                    let values = try (0..<length).map { _ in
                        guard try u1() == 115 else { throw Invalid() }
                        return try text(Int(u2()))
                    }
                    if name == "d1" { metadata.data1 = values } else { metadata.data2 = values }
                default:
                    try skipAnnotationValue(tag: tag)
                }
            }
            return metadata
        }
        return nil
    }

    private mutating func annotationInt() throws -> Int32 {
        guard case let .int(value)? = constants[Int(try u2())] else { throw Invalid() }
        return value
    }

    private mutating func skipAnnotationValue(tag: UInt8, depth: Int = 0) throws {
        guard depth < 64 else { throw Invalid() }
        switch tag {
        case 66, 67, 68, 70, 73, 74, 83, 90, 99, 115: // Primitive, class and string.
            try skip(2)
        case 101: // Enum.
            try skip(4)
        case 64: // Annotation.
            try skip(2)
            let count = try u2()
            for _ in 0..<count {
                try skip(2)
                try skipAnnotationValue(tag: u1(), depth: depth + 1)
            }
        case 91: // Array.
            let count = try u2()
            for _ in 0..<count { try skipAnnotationValue(tag: u1(), depth: depth + 1) }
        default:
            throw Invalid()
        }
    }

    mutating func readAnnotations(visible: Bool = true) throws -> [JVMAnnotation] {
        let count = Int(try u2())
        return try (0..<count).map { _ in
            var annotation = try readAnnotation()
            annotation.visible = visible
            return annotation
        }
    }

    private mutating func readAnnotation() throws -> JVMAnnotation {
        let descriptor = try text(Int(try u2()))
        let pairCount = Int(try u2())
        var values: [(String, JVMAnnotationValue)] = []
        for _ in 0..<pairCount {
            let name = try text(Int(try u2()))
            values.append((name, try readAnnotationValue(tag: u1())))
        }
        return JVMAnnotation(descriptor: descriptor, values: values)
    }

    private mutating func readAnnotationValue(tag: UInt8, depth: Int = 0) throws -> JVMAnnotationValue {
        guard depth < 64 else { throw Invalid() }
        switch tag {
        case 66, 67, 83: // byte, char, short
            let index = Int(try u2())
            guard case let .int(value)? = constants[index] else { throw Invalid() }
            return .integral(value, tag)
        case 73: // int
            return try primitiveAnnotationConstant()
        case 74: // long
            return try primitiveAnnotationConstant()
        case 70: // float
            return try primitiveAnnotationConstant()
        case 68: // double
            return try primitiveAnnotationConstant()
        case 90: // boolean
            let index = Int(try u2())
            guard case let .int(value)? = constants[index] else { throw Invalid() }
            return .constant(.boolean(value != 0))
        case 115: // String
            let index = Int(try u2())
            if let string = strings[index] { return .constant(.string(string)) }
            guard case let .string(string)? = constants[index] else { throw Invalid() }
            return .constant(.string(string))
        case 101: // enum
            return .enumEntry(try text(Int(try u2())), try text(Int(try u2())))
        case 99: // class
            return .classType(try text(Int(try u2())))
        case 64: // annotation
            return .annotation(try readAnnotation())
        case 91: // array
            let count = Int(try u2())
            return .array(try (0..<count).map { _ in try readAnnotationValue(tag: u1(), depth: depth + 1) })
        default:
            throw Invalid()
        }
    }

    private mutating func primitiveAnnotationConstant() throws -> JVMAnnotationValue {
        let index = Int(try u2())
        guard let value = constants[index] else { throw Invalid() }
        switch value {
        case let .int(number): return .constant(.int(number))
        case let .long(number): return .constant(.long(number))
        case let .float(number): return .constant(.float(number))
        case let .double(number): return .constant(.double(number))
        case let .string(string): return .constant(.string(string))
        }
    }

    private static func classTypeParameterNames(in signature: String?) throws -> [String] {
        guard let signature, signature.first == "<" else { return [] }
        let scalars = Array(signature)
        var index = 1
        var names: [String] = []

        func parseReferenceType() throws {
            guard index < scalars.count else { throw Invalid() }
            switch scalars[index] {
            case "[":
                index += 1
                try parseType()
            case "T":
                index += 1
                while index < scalars.count, scalars[index] != ";" { index += 1 }
                guard index < scalars.count else { throw Invalid() }
                index += 1
            case "L":
                index += 1
                while index < scalars.count {
                    switch scalars[index] {
                    case ";": index += 1; return
                    case "<":
                        index += 1
                        while index < scalars.count, scalars[index] != ">" {
                            if scalars[index] == "*" { index += 1; continue }
                            if scalars[index] == "+" || scalars[index] == "-" { index += 1 }
                            try parseReferenceType()
                        }
                        guard index < scalars.count else { throw Invalid() }
                        index += 1
                    default: index += 1
                    }
                }
                throw Invalid()
            default: throw Invalid()
            }
        }
        func parseType() throws {
            guard index < scalars.count else { throw Invalid() }
            if "BCDFIJSZ".contains(scalars[index]) { index += 1; return }
            try parseReferenceType()
        }

        while index < scalars.count, scalars[index] != ">" {
            let start = index
            while index < scalars.count, scalars[index] != ":" { index += 1 }
            guard index < scalars.count, index > start else { throw Invalid() }
            let name = String(scalars[start..<index])
            guard JVMProgramBuilder.isIdentifier(name) else { throw Invalid() }
            names.append(name)
            index += 1
            if index < scalars.count, scalars[index] != ":" { try parseReferenceType() }
            while index < scalars.count, scalars[index] == ":" {
                index += 1
                try parseReferenceType()
            }
        }
        guard index < scalars.count, scalars[index] == ">" else { throw Invalid() }
        return names
    }

    mutating func read() throws -> JVMClassInfo {
        guard try u4() == 0xCAFEBABE else { throw Invalid() }
        _ = try u2(); guard try u2() >= 45 else { throw Invalid() }
        let count = Int(try u2())
        var index = 1
        var hasKotlinMetadata = false
        var hasJvmOverloads = false
        var hasMetroAnnotation = false
        var hasComposableAnnotation = false
        // CONSTANT_String may reference a Utf8 entry declared later in the
        // pool; resolve those references once the pool is fully read.
        var pendingStringRefs: [Int: Int] = [:]
        while index < count {
            switch try u1() {
            case 1:
                let length = Int(try u2()); guard length <= bytes.count - offset else { throw Invalid() }
                var units: [UInt16] = []
                let end = offset + length
                while offset < end {
                    let first = try u1()
                    if first > 0 && first < 128 { units.append(UInt16(first)) }
                    else if first & 0xE0 == 0xC0 {
                        guard offset < end else { throw Invalid() }; let b = try u1()
                        guard b & 0xC0 == 0x80 else { throw Invalid() }
                        units.append(UInt16(first & 31) << 6 | UInt16(b & 63))
                    } else if first & 0xF0 == 0xE0 {
                        guard offset + 1 < end else { throw Invalid() }; let b = try u1(), c = try u1()
                        guard b & 0xC0 == 0x80, c & 0xC0 == 0x80 else { throw Invalid() }
                        units.append(UInt16(first & 15) << 12 | UInt16(b & 63) << 6 | UInt16(c & 63))
                    } else { throw Invalid() }
                }
                let string = String(decoding: units, as: UTF16.self)
                strings[index] = string
                if string == "Lkotlin/Metadata;" { hasKotlinMetadata = true }
                if string == "Lkotlin/jvm/JvmOverloads;" { hasJvmOverloads = true }
                if string == "Landroidx/compose/runtime/Composable;" { hasComposableAnnotation = true }
                if !hasMetroAnnotation, string.hasPrefix(JVMMetro.annotationPrefix),
                   (string == JVMMetro.invoke || JVMMetro.annotationDescriptors.contains(string)) {
                    hasMetroAnnotation = true
                }
            case 7: classes[index] = Int(try u2())
            case 3:
                constants[index] = .int(Int32(bitPattern: try u4()))
            case 4:
                constants[index] = .float(Float(bitPattern: try u4()))
            case 5:
                guard index + 1 < count else { throw Invalid() }
                let high = try u4(), low = try u4()
                constants[index] = .long(Int64(bitPattern: (UInt64(high) << 32) | UInt64(low)))
                index += 1
            case 6:
                guard index + 1 < count else { throw Invalid() }
                let high = try u4(), low = try u4()
                constants[index] = .double(Double(bitPattern: (UInt64(high) << 32) | UInt64(low)))
                index += 1
            case 8:
                pendingStringRefs[index] = Int(try u2())
            case 16, 19, 20: try skip(2)
            case 9, 10, 11, 12, 17, 18: try skip(4)
            case 15: try skip(3)
            default: throw Invalid()
            }
            index += 1
        }
        for (slot, ref) in pendingStringRefs {
            if let value = strings[ref] { constants[slot] = .string(value) }
        }
        let flags = try u2(), this = try u2(), base = try u2()
        let name = try className(Int(this))
        let superclass = base == 0 ? nil : try className(Int(base))
        var interfaces: [String] = []
        let interfaceCount = try u2()
        for _ in 0..<interfaceCount { interfaces.append(try className(Int(u2()))) }
        let fieldCount = try u2()
        var fields: [JVMForeignField] = []
        for _ in 0..<fieldCount {
            let access = try u2(), nameIndex = try u2(), descriptorIndex = try u2()
            let fieldName = try text(Int(nameIndex)), descriptor = try text(Int(descriptorIndex))
            var field = JVMForeignField(name: fieldName, descriptor: descriptor, access: access)
            field.constantValue = try fieldAttributes()
            fields.append(field)
        }
        var methods: [JVMForeignMethod] = []
        var bridgeMethods: [JVMForeignMethod] = []
        var defaultArgumentMethods: [JVMForeignMethod] = []
        var syntheticConstructors: [JVMForeignMethod] = []
        var metroAccessors: [JVMForeignMethod] = []
        let methodCount = try u2()
        let parseAnnotations = flags & 0x2000 != 0 || hasMetroAnnotation
        for _ in 0..<methodCount {
            let access = try u2(), nameIndex = try u2(), descriptorIndex = try u2()
            let methodName = try text(Int(nameIndex)), descriptor = try text(Int(descriptorIndex))
            let methodInfo = try methodAttributes(
                parseAnnotations: parseAnnotations || hasComposableAnnotation || hasJvmOverloads, parseParameters: hasMetroAnnotation
            )
            let isDefaultArgumentMethod = access & 0x1009 == 0x1009 && methodName.hasSuffix("$default")
            let isSyntheticConstructor = hasKotlinMetadata && access & 0x1001 == 0x1001 && methodName == "<init>"
                && descriptor.hasSuffix("Lkotlin/jvm/internal/DefaultConstructorMarker;)V")
            let isValueAdapter = hasKotlinMetadata && ["box-impl", "unbox-impl", "constructor-impl"].contains(methodName)
            let isReifiedGlanceAction = hasKotlinMetadata && name == "androidx/glance/action/StartActivityActionKt"
                && methodName == "actionStartActivity" && descriptor == "(Landroidx/glance/action/ActionParameters;)Landroidx/glance/action/Action;"
            let isReifiedWorkBuilder = hasKotlinMetadata && name == "androidx/work/OneTimeWorkRequestKt"
                && methodName == "OneTimeWorkRequestBuilder" && descriptor == "()Landroidx/work/OneTimeWorkRequest$Builder;"
            let isReifiedContextService = hasKotlinMetadata && access & 0x1009 == 0x1009
                && JVMAndroidXContextService.isEntry(owner: name, name: methodName, descriptor: descriptor)
            let isReifiedHiltViewModel = hasKotlinMetadata && access & 0x1009 == 0x1009
                && JVMClasspathIndex.isReifiedHiltViewModel(owner: name, name: methodName, descriptor: descriptor)
            let isMetroAccessor = hasMetroAnnotation && ((methodInfo.annotations.contains { $0.descriptor == JVMMetro.provides } || methodName == "<init>") && access & 0x0002 != 0
                || access & 0x1009 == 0x1009 && methodName.hasPrefix("access$"))
            if isMetroAccessor || (access & 0x0005 != 0 && (access & 0x1040 == 0 || access & 0x0040 != 0 || isDefaultArgumentMethod || isValueAdapter || isSyntheticConstructor || isReifiedGlanceAction || isReifiedWorkBuilder || isReifiedContextService || isReifiedHiltViewModel)), methodName != "<clinit>",
               let signature = try? JVMDescriptor.parse(descriptor),
               signature.0.reduce(0, { $0 + $1.width }) <= (access & 8 != 0 ? 255 : 254) {
                var method = JVMForeignMethod(owner: name, name: methodName, descriptor: descriptor,
                    parameters: signature.0, result: methodName == "<init>" ? .reference(name, nullable: false) : signature.1,
                    isStatic: access & 8 != 0, isInterface: flags & 0x0200 != 0, isAbstract: access & 0x0400 != 0)
                method.isFinal = access & 16 != 0
                method.isProtected = access & 0x0004 != 0
                method.isVarargs = access & 0x0080 != 0
                method.genericResultParameter = Self.genericResultParameter(in: methodInfo.signature, method: method)
                if name == "androidx/work/WorkRequest$Builder", let signature = methodInfo.signature {
                    for parameter in ["B", "W"] where signature.hasSuffix(")T\(parameter);") {
                        method.kotlinOwnerResultParameter = parameter
                    }
                }
                method.annotations = methodInfo.annotations
                method.annotationDefault = methodInfo.annotationDefault
                method.parameterAnnotations = methodInfo.parameterAnnotations
                method.genericSignature = methodInfo.signature
                if isMetroAccessor { metroAccessors.append(method) }
                else if isSyntheticConstructor { syntheticConstructors.append(method) }
                else if isDefaultArgumentMethod { defaultArgumentMethods.append(method) }
                else if access & 0x0040 != 0 { bridgeMethods.append(method) }
                else { methods.append(method) }
            }
        }
        let classAttributes = try classAttributes(hasKotlinMetadata: hasKotlinMetadata, parseAnnotations: parseAnnotations)
        guard offset == bytes.count else { throw Invalid() }
        if let metadata = classAttributes.kotlinMetadata,
           methods.contains(where: { $0.isConstructor && !$0.parameters.isEmpty }),
           let constructors = try? metadata.constructorParameterNames(byteLimit: bytes.count) {
            for index in methods.indices where methods[index].isConstructor {
                if let names = constructors[methods[index].descriptor], names.count == methods[index].parameters.count {
                    methods[index].kotlinConstructorParameterNames = names
                }
            }
        }
        let valueCarrier = methods.first(where: { !$0.isStatic && $0.name == "unbox-impl" && $0.parameters.isEmpty })?.result
        let hasValueAdapters = valueCarrier.map { carrier in
            methods.contains { $0.isStatic && $0.name == "box-impl" && $0.descriptor == "(" + carrier.descriptor + ")L" + name + ";" }
        } ?? false
        var readOnlyCollectionSupertypes: [String: String] = [:]
        if flags & 0x0200 != 0, let metadata = classAttributes.kotlinMetadata,
           interfaces.contains(where: { $0 == "kotlin/jvm/internal/markers/KMappedMarker" }) {
            readOnlyCollectionSupertypes = (try? metadata.readOnlyCollectionSupertypes(byteLimit: bytes.count)) ?? [:]
        }
        let hasReadOnlyListSupertype = readOnlyCollectionSupertypes["java/util/List"] != nil
        let hasReadOnlyMapSupertype = readOnlyCollectionSupertypes["java/util/Map"] != nil
        if let metadata = classAttributes.kotlinMetadata,
           methods.contains(where: Self.hasSuspendDescriptor),
           let functions = try? metadata.suspendFunctions(byteLimit: bytes.count) {
            for index in methods.indices where Self.hasSuspendDescriptor(methods[index]) {
                let method = methods[index]
                guard let function = functions[method.name + method.descriptor],
                      method.parameters.count == function.parameters.count + (function.receiverIsNullable == nil ? 1 : 2)
                else { continue }
                methods[index].kotlinSuspendFunction = function
            }
        }
        let isMetroFactory = classAttributes.annotations.contains { $0.descriptor == JVMMetro.factory }
        let functionTypeMemberNames = Set(methods.lazy.filter(Self.hasFunctionTypeDescriptor).map(\.name))
        let defaultMethodNames = Set(defaultArgumentMethods.map { String($0.name.dropLast("$default".count)) })
        let typedFlowMemberNames = Set(methods.lazy.filter {
            !$0.isStatic && $0.genericSignature?.contains(")Lkotlinx/coroutines/flow/Flow<") == true
        }.map(\.name))
        let composableMemberNames = Set(methods.lazy.filter {
            !$0.isStatic && $0.annotations.contains { $0.descriptor == "Landroidx/compose/runtime/Composable;" }
        }.map(\.name))
        if let metadata = classAttributes.kotlinMetadata,
           (metadata.isFileFacade == true || isMetroFactory || hasValueAdapters || !metroAccessors.isEmpty
               || methods.contains(where: { Self.hasFunctionTypeDescriptor($0) || !$0.isStatic && (!$0.parameters.isEmpty || $0.isFinal) })),
           let functions = try? metadata.functions(
               byteLimit: bytes.count, isValueClass: hasValueAdapters, hasReadOnlyListSupertype: hasReadOnlyListSupertype,
               functionTypeMemberNames: functionTypeMemberNames.union(typedFlowMemberNames), defaultMethodNames: defaultMethodNames,
               composableMemberNames: composableMemberNames, metroFactory: isMetroFactory, ownerIsInterface: flags & 0x0200 != 0,
               ownerIsSAM: flags & 0x0200 != 0 && methods.filter { $0.isAbstract && !$0.isStatic }.count == 1
           ) {
            for index in methods.indices {
                let method = methods[index]
                guard let function = functions.first(where: { candidate in
                          guard (candidate.jvmName ?? candidate.name) == method.name,
                                candidate.descriptor == nil || candidate.descriptor == method.descriptor else { return false }
                          if let parameters = candidate.valueOperatorParameterDescriptors {
                              return method.isStatic && method.parameters.count == parameters.count + 1
                                  && method.parameters.first?.descriptor == valueCarrier?.descriptor
                          }
                          if method.kotlinSuspendFunction != nil {
                              return metadata.isFileFacade == true && method.isStatic && candidate.isSuspend
                                  && candidate.contextParameters.isEmpty
                                  && (!candidate.composableParameters.isEmpty || !candidate.typeParameters.isEmpty)
                                  && candidate.parameters.count + candidate.leadingParameterCount + 1 == method.parameters.count
                          }
                          return !candidate.isSuspend
                              && (metadata.isFileFacade == true && method.isStatic || Self.hasFunctionTypeDescriptor(method)
                                  || method.composeABI(for: candidate) != nil
                                  || typedFlowMemberNames.contains(method.name) && candidate.descriptor == method.descriptor
                                  || !method.isStatic && candidate.contextParameters.isEmpty
                                      && (candidate.receiver != nil || (defaultMethodNames.contains(method.name)
                                          && candidate.parameters.contains(where: \.hasDefaultValue)
                                          || candidate.isInfix || candidate.isOperator || hasReadOnlyListSupertype
                                          && candidate.name == "subList" || method.isFinal && candidate.isGenericFinalGetter
                                          || candidate.hasStableFinalParameters
                                          || candidate.mangledMemberParameterDescriptors != nil)
                                          && candidate.descriptor != nil))
                              && (candidate.parameters.count + candidate.leadingParameterCount == method.parameters.count
                                  || method.composeABI(for: candidate) != nil)
                      })
                else { continue }
                methods[index].kotlinFunction = function
            }
            for index in metroAccessors.indices {
                let method = metroAccessors[index]
                guard method.annotations.contains(where: { $0.descriptor == JVMMetro.provides }) else { continue }
                metroAccessors[index].kotlinFunction = functions.first {
                    ($0.jvmName ?? $0.name) == method.name && $0.descriptor == method.descriptor
                }
            }
        }
        if classAttributes.kotlinMetadata != nil, hasJvmOverloads {
            let methodsByParameters = Dictionary(grouping: methods) { method in
                method.name + method.descriptor.prefix(through: method.descriptor.firstIndex(of: ")")!)
            }
            methods.removeAll { method in
                guard !method.isConstructor,
                      method.annotations.contains(where: { $0.descriptor == "Lkotlin/jvm/JvmOverloads;" }) else { return false }
                let key = method.name + method.descriptor.prefix(through: method.descriptor.firstIndex(of: ")")!)
                return methodsByParameters[key]?.contains { other in
                    other.descriptor != method.descriptor
                        && !other.annotations.contains { $0.descriptor == "Lkotlin/jvm/JvmOverloads;" }
                } == true
            }
        }
        if let metadata = classAttributes.kotlinMetadata, metadata.isFileFacade == false {
            let duplicateGroups = Dictionary(grouping: methods.filter { !$0.isConstructor && !$0.isStatic }) {
                $0.name + $0.descriptor.prefix(through: $0.descriptor.firstIndex(of: ")")!)
            }.values.filter { $0.count > 1 }
            if !duplicateGroups.isEmpty,
               let sourceNames = try? metadata.collidingMemberSourceNames(byteLimit: bytes.count) {
                var ignored: Set<String> = []
                var renamed: [String: String] = [:]
                for group in duplicateGroups {
                    let names = group.compactMap { method in sourceNames[method.name + method.descriptor] }
                    guard !names.isEmpty, Set(names).count == names.count else { continue }
                    for method in group {
                        let key = method.name + method.descriptor
                        if let sourceName = sourceNames[key] {
                            if sourceName != method.name { renamed[key] = sourceName }
                        } else {
                            ignored.insert(key)
                        }
                    }
                }
                methods.removeAll { ignored.contains($0.name + $0.descriptor) }
                for index in methods.indices {
                    methods[index].kotlinCollisionSourceName = renamed[methods[index].name + methods[index].descriptor]
                }
            }
        }
        var info = JVMClassInfo(
            name: name,
            flags: flags,
            superclass: superclass,
            interfaces: interfaces,
            methods: methods,
            fields: fields,
            bridgeMethods: bridgeMethods,
            defaultArgumentMethods: defaultArgumentMethods,
            classTypeParameterNames: try Self.classTypeParameterNames(in: classAttributes.signature),
            innerClasses: classAttributes.innerClasses,
            hasInnerClassesAttribute: classAttributes.hasInnerClassesAttribute,
            hasEnclosingMethod: classAttributes.hasEnclosingMethod,
            isKotlinFileFacade: classAttributes.kotlinMetadata?.isFileFacade,
            annotations: classAttributes.annotations
        )
        info.kotlinMultifileParts = classAttributes.kotlinMetadata?.multifileParts ?? []
        info.isKotlinMultifilePart = classAttributes.kotlinMetadata?.isMultifilePart == true
        info.genericSignature = classAttributes.signature
        info.metroAccessors = metroAccessors
        if !info.classTypeParameterNames.isEmpty, let metadata = classAttributes.kotlinMetadata {
            info.kotlinTypeParameterVariance = (try? metadata.classTypeParameterVariance(byteLimit: bytes.count)) ?? [:]
        }
        info.kotlinReadOnlyCollectionSupertypes = readOnlyCollectionSupertypes
        if classAttributes.signature?.contains("<") == true, let metadata = classAttributes.kotlinMetadata {
            info.kotlinParameterizedSupertypes = (try? metadata.parameterizedSupertypes(byteLimit: bytes.count)) ?? [:]
        }
        if hasValueAdapters, interfaces.contains("java/lang/Comparable"), let metadata = classAttributes.kotlinMetadata {
            info.kotlinComparableSupertype = try? metadata.comparableSupertype(byteLimit: bytes.count)
        }
        if hasValueAdapters, let valueCarrier, let metadata = classAttributes.kotlinMetadata,
           let constructors = try? metadata.valueClassConstructors(byteLimit: bytes.count) {
            for constructor in constructors {
                guard let adapter = methods.first(where: {
                    $0.name == "constructor-impl" && $0.isStatic && !$0.isProtected
                        && $0.descriptor == constructor.descriptor && $0.result.descriptor == valueCarrier.descriptor
                        && $0.parameters.count == constructor.parameters.count
                }) else { continue }
                info.kotlinValueClassConstructors.append((constructor, adapter))
            }
        }
        if !syntheticConstructors.isEmpty, let metadata = classAttributes.kotlinMetadata,
           let constructors = try? metadata.constructorsWithLoweredParameters(byteLimit: bytes.count) {
            let marker = "Lkotlin/jvm/internal/DefaultConstructorMarker;)V"
            for constructor in constructors {
                let prefix = String(constructor.descriptor.dropLast(2))
                let maskCount = (constructor.parameters.count + 31) / 32
                let defaultDescriptor = prefix + String(repeating: "I", count: maskCount) + marker
                let defaults = syntheticConstructors.first { $0.descriptor == defaultDescriptor }
                if let entry = methods.first(where: { $0.isConstructor && $0.descriptor == constructor.descriptor }) {
                    guard defaults != nil else { continue }
                    info.kotlinLoweredConstructors.append((constructor, entry, defaults))
                } else if let entry = syntheticConstructors.first(where: { $0.descriptor == prefix + marker }) {
                    info.kotlinLoweredConstructors.append((constructor, entry, defaults))
                }
            }
        }
        if info.isInterface, let metadata = classAttributes.kotlinMetadata {
            info.kotlinSealedInterfaceSubclasses = (try? metadata.sealedInterfaceSubclasses(byteLimit: bytes.count)) ?? []
        }
        if info.isKotlinMultifilePart || fields.contains(where: { $0.isStatic && $0.isFinal && $0.constantValue != nil }),
           let metadata = classAttributes.kotlinMetadata {
            info.kotlinTopLevelConstants = (try? metadata.topLevelConstants(byteLimit: bytes.count)) ?? [:]
        }
        if let metadata = classAttributes.kotlinMetadata, let properties = try? metadata.topLevelProperties(byteLimit: bytes.count) {
            for property in properties {
                guard let getter = methods.first(where: {
                    $0.isStatic && !$0.isProtected && $0.name == property.getterName && $0.descriptor == property.getterDescriptor
                        && ($0.parameters.count == (property.receiver == nil ? 0 : 1)
                            || $0.composePropertyABI(hasReceiver: property.receiver != nil)) && $0.result != .unit
                }) else { continue }
                info.kotlinTopLevelProperties.append((property, getter))
            }
        }
        let isKotlinObject = fields.contains { $0.name == "INSTANCE" && $0.isPublic && $0.isStatic && $0.descriptor == "L\(name);" }
        if isKotlinObject, let metadata = classAttributes.kotlinMetadata {
            info.isKotlinObject = (try? metadata.isObject(byteLimit: bytes.count)) == true
        }
        if let metadata = classAttributes.kotlinMetadata,
           hasReadOnlyMapSupertype || isKotlinObject || flags & 0x0200 != 0 || name.hasSuffix("$Companion") || methods.contains(where: {
               $0.name.hasPrefix("get") && ($0.name.contains("-")
                   || flags & 0x0200 != 0 && $0.isAbstract && $0.result.referenceName == "kotlinx/coroutines/flow/StateFlow")
                   || !$0.isStatic && $0.composePropertyABI(hasReceiver: false)
                   || $0.isFinal && !$0.isStatic && $0.parameters.isEmpty
                       && ($0.name.hasPrefix("get") || $0.name.hasPrefix("is"))
           }),
           let properties = try? metadata.classPropertyCandidates(byteLimit: bytes.count) {
            for property in properties {
                guard let getter = methods.first(where: {
                    !$0.isProtected && $0.name == property.getterName && $0.descriptor == property.getterDescriptor && $0.result != .unit
                }) else { continue }
                if isKotlinObject && getter.isStatic && getter.parameters.isEmpty {
                    // Kotlin objects may expose a property's accessor only as @JvmStatic.
                    info.kotlinStaticProperties[property.name] = (getter, property.isNullable)
                } else if let sourceType = property.sourceType,
                          (name.hasSuffix("$Companion") || getter.name.contains("-")
                              || isKotlinObject && property.isSourceVisible && !property.isVar
                              || hasReadOnlyMapSupertype && !property.isVar && ["keys", "values", "entries"].contains(property.name)
                              || flags & 0x0200 != 0 && getter.isAbstract && !property.isVar && property.isSourceVisible
                              || !getter.isStatic && property.isSourceVisible && !property.isVar
                                  && getter.composePropertyABI(hasReceiver: false)
                              || getter.isFinal && !property.isVar
                                  && (sourceType.contains("<") || getter.name == property.name)),
                          !getter.isStatic && (getter.parameters.isEmpty || getter.composePropertyABI(hasReceiver: false))
                              || hasValueAdapters && getter.isStatic && getter.parameters.map(\.descriptor) == [valueCarrier?.descriptor] {
                    info.kotlinMemberProperties[property.name] = (getter, sourceType)
                }
            }
        }
        return info
    }

    private static func hasSuspendDescriptor(_ method: JVMForeignMethod) -> Bool {
        method.result.referenceName == "java/lang/Object"
            && method.parameters.last?.referenceName == "kotlin/coroutines/Continuation"
    }

    private static func hasFunctionTypeDescriptor(_ method: JVMForeignMethod) -> Bool {
        (method.parameters + [method.result]).contains { type in
            guard let name = type.referenceName else { return false }
            return name.hasPrefix("kotlin/jvm/functions/Function")
                || name.hasPrefix("kotlin/jvm/functions/SuspendFunction")
                || name.hasPrefix("kotlin/coroutines/SuspendFunction")
        }
    }
}

enum JVMDescriptor {
    static func parse(_ descriptor: String) throws -> ([JVMValueType], JVMValueType) {
        let bytes = Array(descriptor.utf8)
        var i = 0
        var arrayDepth = 0
        func type() throws -> JVMValueType {
            guard i < bytes.count else { throw JVMClassReader.Invalid() }
            let byte = bytes[i]; i += 1
            switch byte {
            case 66: return .byte
            case 83: return .short
            case 67: return .char
            case 73: return .int
            case 74: return .long
            case 70: return .float
            case 68: return .double
            case 90: return .boolean
            case 86: return .unit
            case 91:
                guard arrayDepth < 255 else { throw JVMClassReader.Invalid() }
                arrayDepth += 1; defer { arrayDepth -= 1 }
                let component = try type()
                guard component != .unit else { throw JVMClassReader.Invalid() }
                return .reference("[" + component.descriptor, nullable: true)
            case 76:
                let start = i
                while i < bytes.count, bytes[i] != 59 { i += 1 }
                guard i < bytes.count, i > start else { throw JVMClassReader.Invalid() }
                let name = String(decoding: bytes[start..<i], as: UTF8.self); i += 1
                // Binary names may nest with '$' (a/b/C$D); each segment
                // must still be a valid identifier so anonymous classes
                // (C$1) and other unnameable shapes stay rejected.
                guard name.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ segment in
                    segment.split(separator: "$", omittingEmptySubsequences: false)
                        .allSatisfy { JVMProgramBuilder.isIdentifier(String($0)) }
                }) else { throw JVMClassReader.Invalid() }
                return .reference(name, nullable: true)
            default: throw JVMClassReader.Invalid()
            }
        }
        guard bytes.first == 40 else { throw JVMClassReader.Invalid() }; i += 1
        var parameters: [JVMValueType] = []
        while i < bytes.count, bytes[i] != 41 {
            let t = try type(); guard t != .unit else { throw JVMClassReader.Invalid() }; parameters.append(t)
        }
        guard i < bytes.count else { throw JVMClassReader.Invalid() }; i += 1
        let result = try type()
        guard i == bytes.count else { throw JVMClassReader.Invalid() }
        return (parameters, result)
    }
}

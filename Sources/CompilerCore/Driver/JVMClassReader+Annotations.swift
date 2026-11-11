extension JVMClassReader {
    mutating func readAnnotation(visible: Bool, depth: Int = 0) throws -> JVMAnnotation {
        guard depth < 64 else { throw Invalid() }
        let descriptor = try text(Int(u2()))
        let count = Int(try u2())
        var values: [(String, JVMAnnotationValue)] = []
        for _ in 0..<count {
            let name = try text(Int(u2()))
            values.append((name, try readAnnotationValue(depth: depth + 1)))
        }
        return JVMAnnotation(descriptor: descriptor, values: values, visible: visible)
    }

    mutating func readAnnotationValue(depth: Int = 0) throws -> JVMAnnotationValue {
        guard depth < 64 else { throw Invalid() }
        let tag = try u1()
        switch tag {
        case 64: // @
            return .annotation(try readAnnotation(visible: true, depth: depth + 1))
        case 91: // [
            let count = Int(try u2())
            return .array(try (0..<count).map { _ in try readAnnotationValue(depth: depth + 1) })
        case 99: // c
            return .classType(try text(Int(u2())))
        case 101: // e
            return .enumEntry(try text(Int(u2())), try text(Int(u2())))
        case 115: // s
            return .constant(.string(try text(Int(u2()))))
        default:
            let index = Int(try u2())
            switch (tag, constants[index]) {
            case (66, .int(let value)), (67, .int(let value)), (83, .int(let value)):
                return .integral(value, tag)
            case (73, .int(let value)): return .constant(.int(value))
            case (90, .int(let value)): return .constant(.boolean(value != 0))
            case (74, .long(let value)): return .constant(.long(value))
            case (70, .float(let value)): return .constant(.float(value))
            case (68, .double(let value)): return .constant(.double(value))
            default: throw Invalid()
            }
        }
    }
}

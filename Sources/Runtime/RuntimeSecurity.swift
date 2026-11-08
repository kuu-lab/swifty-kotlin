import Foundation
#if canImport(Security)
import Security
import CryptoKit
import CommonCrypto
#endif

private func runtimeSecurityBytes(from raw: Int) -> [UInt8]? {
    guard let array = runtimeArrayBox(from: raw) else { return nil }
    return (0 ..< array.count).map { UInt8(truncatingIfNeeded: array[$0]) }
}

private func runtimeSecurityWrite(_ bytes: [UInt8], to raw: Int) -> Bool {
    guard let array = runtimeArrayBox(from: raw), array.count >= bytes.count else { return false }
    for (index, byte) in bytes.enumerated() {
        array[index] = Int(Int8(bitPattern: byte))
    }
    return true
}

private func derLength(_ count: Int) -> [UInt8] {
    if count < 128 { return [UInt8(count)] }
    var value = count
    var encoded: [UInt8] = []
    while value > 0 {
        encoded.insert(UInt8(value & 0xff), at: 0)
        value >>= 8
    }
    return [0x80 | UInt8(encoded.count)] + encoded
}

private func derElement(_ tag: UInt8, _ payload: [UInt8]) -> [UInt8] {
    [tag] + derLength(payload.count) + payload
}

private func wrapPKCS8(_ pkcs1: [UInt8]) -> [UInt8] {
    let rsaAlgorithmIdentifier: [UInt8] = [
        0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00,
    ]
    return derElement(0x30, derElement(0x02, [0x00]) + rsaAlgorithmIdentifier + derElement(0x04, pkcs1))
}

private func wrapX509(_ pkcs1: [UInt8]) -> [UInt8] {
    let rsaAlgorithmIdentifier: [UInt8] = [
        0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00,
    ]
    return derElement(0x30, rsaAlgorithmIdentifier + derElement(0x03, [0x00] + pkcs1))
}

private func readDERElement(_ bytes: [UInt8], at start: Int) -> (tag: UInt8, payload: Range<Int>, end: Int)? {
    guard start >= 0, start + 2 <= bytes.count else { return nil }
    let tag = bytes[start]
    var index = start + 1
    let firstLength = Int(bytes[index])
    index += 1
    let length: Int
    if firstLength & 0x80 == 0 {
        length = firstLength
    } else {
        let lengthBytes = firstLength & 0x7f
        guard lengthBytes > 0, lengthBytes <= 4, index + lengthBytes <= bytes.count else { return nil }
        var decoded = 0
        for _ in 0 ..< lengthBytes {
            decoded = (decoded << 8) | Int(bytes[index])
            index += 1
        }
        length = decoded
    }
    guard length >= 0, index <= bytes.count - length else { return nil }
    return (tag, index ..< index + length, index + length)
}

private func unwrapPKCS8(_ bytes: [UInt8]) -> [UInt8]? {
    guard let sequence = readDERElement(bytes, at: 0), sequence.tag == 0x30,
          let version = readDERElement(bytes, at: sequence.payload.lowerBound), version.tag == 0x02,
          let algorithm = readDERElement(bytes, at: version.end), algorithm.tag == 0x30,
          let key = readDERElement(bytes, at: algorithm.end), key.tag == 0x04,
          sequence.end == bytes.count else { return nil }
    return Array(bytes[key.payload])
}

private func unwrapX509(_ bytes: [UInt8]) -> [UInt8]? {
    guard let sequence = readDERElement(bytes, at: 0), sequence.tag == 0x30,
          let algorithm = readDERElement(bytes, at: sequence.payload.lowerBound), algorithm.tag == 0x30,
          let key = readDERElement(bytes, at: algorithm.end), key.tag == 0x03,
          key.payload.count > 1, bytes[key.payload.lowerBound] == 0,
          sequence.end == bytes.count else { return nil }
    return Array(bytes[(key.payload.lowerBound + 1) ..< key.payload.upperBound])
}

private func derOID(_ arcs: [UInt64]) -> [UInt8] {
    guard arcs.count >= 2 else { return [] }
    func encodeArc(_ value: UInt64) -> [UInt8] {
        var remaining = value
        var result: [UInt8] = [UInt8(remaining & 0x7f)]
        remaining >>= 7
        while remaining > 0 {
            result.insert(UInt8(remaining & 0x7f) | 0x80, at: 0)
            remaining >>= 7
        }
        return result
    }
    var body = encodeArc(arcs[0] * 40 + arcs[1])
    for arc in arcs.dropFirst(2) { body += encodeArc(arc) }
    return derElement(0x06, body)
}

private func derInteger(_ value: Int) -> [UInt8] {
    var remaining = value
    var bytes: [UInt8] = []
    repeat {
        bytes.insert(UInt8(remaining & 0xff), at: 0)
        remaining >>= 8
    } while remaining != 0
    if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
    return derElement(0x02, bytes)
}

private func derSequence(_ elements: [[UInt8]]) -> [UInt8] {
    derElement(0x30, elements.flatMap { $0 })
}

private func derSet(_ elements: [[UInt8]]) -> [UInt8] {
    derElement(0x31, elements.sorted { $0.lexicographicallyPrecedes($1) }.flatMap { $0 })
}

private func derAttribute(_ oid: [UInt64], value: [UInt8]) -> [UInt8] {
    derSequence([derOID(oid), derSet([value])])
}

private func pkcs12ContentInfo(_ content: [UInt8]) -> [UInt8] {
    derSequence([derOID([1, 2, 840, 113549, 1, 7, 1]), derElement(0xa0, derElement(0x04, content))])
}

private func appendSecurityUInt32(_ value: Int, to bytes: inout [UInt8]) -> Bool {
    guard value >= 0, value <= Int(UInt32.max) else { return false }
    let value = UInt32(value)
    bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    bytes.append(UInt8(truncatingIfNeeded: value >> 16))
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
    return true
}

private func appendSecurityField(_ field: [UInt8], to bytes: inout [UInt8]) -> Bool {
    guard appendSecurityUInt32(field.count, to: &bytes) else { return false }
    bytes.append(contentsOf: field)
    return true
}

private struct SecurityWireReader {
    let bytes: [UInt8]
    var offset = 0

    mutating func readUInt32() -> Int? {
        guard offset <= bytes.count - 4 else { return nil }
        let value = (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
        offset += 4
        return Int(value)
    }

    mutating func readField(maximumLength: Int) -> [UInt8]? {
        guard let length = readUInt32(), length <= maximumLength,
              offset <= bytes.count - length else { return nil }
        let field = Array(bytes[offset ..< offset + length])
        offset += length
        return field
    }
}

#if canImport(Security)
private func securityExpandPKCS12Block(_ source: [UInt8], width: Int) -> [UInt8] {
    guard !source.isEmpty else { return [] }
    let count = width * ((source.count + width - 1) / width)
    return (0 ..< count).map { source[$0 % source.count] }
}

private func securityPKCS12SHA1Key(
    password: [UInt8],
    salt: [UInt8],
    diversifier: UInt8,
    outputCount: Int,
    iterations: Int
) -> [UInt8] {
    let blockSize = 64
    let diversifierBytes = [UInt8](repeating: diversifier, count: blockSize)
    var state = securityExpandPKCS12Block(salt, width: blockSize)
        + securityExpandPKCS12Block(password, width: blockSize)
    var result: [UInt8] = []
    while result.count < outputCount {
        var digest = Array(Insecure.SHA1.hash(data: Data(diversifierBytes + state)))
        if iterations > 1 {
            for _ in 1 ..< iterations { digest = Array(Insecure.SHA1.hash(data: Data(digest))) }
        }
        result.append(contentsOf: digest)
        let adjustment = (0 ..< blockSize).map { digest[$0 % digest.count] }
        if !state.isEmpty {
            for start in stride(from: 0, to: state.count, by: blockSize) {
                var carry = 1
                for index in stride(from: start + blockSize - 1, through: start, by: -1) {
                    let sum = Int(state[index]) + Int(adjustment[index - start]) + carry
                    state[index] = UInt8(sum & 0xff)
                    carry = sum >> 8
                }
            }
        }
    }
    return Array(result.prefix(outputCount))
}

private func securityPKCS12FriendlyName(_ name: String) -> [UInt8] {
    let utf16 = name.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xff)] }
    return derAttribute([1, 2, 840, 113549, 1, 9, 20], value: derElement(0x1e, utf16))
}

private func securityPKCS12LocalKeyID(_ id: [UInt8]) -> [UInt8] {
    derAttribute([1, 2, 840, 113549, 1, 9, 21], value: derElement(0x04, id))
}

private func securityEncryptPKCS8(_ pkcs8: [UInt8], password: String) -> [UInt8]? {
    let iterations = 2048
    var salt = [UInt8](repeating: 0, count: 16)
    var iv = [UInt8](repeating: 0, count: 16)
    guard SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt) == errSecSuccess,
          SecRandomCopyBytes(kSecRandomDefault, iv.count, &iv) == errSecSuccess else { return nil }

    let passwordBytes = Array(password.utf8)
    var key = [UInt8](repeating: 0, count: 32)
    let deriveStatus = passwordBytes.withUnsafeBufferPointer { passwordBuffer in
        salt.withUnsafeBufferPointer { saltBuffer in
            key.withUnsafeMutableBufferPointer { keyBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBuffer.baseAddress.map {
                        UnsafeRawPointer($0).assumingMemoryBound(to: Int8.self)
                    },
                    passwordBuffer.count,
                    saltBuffer.baseAddress,
                    saltBuffer.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    keyBuffer.baseAddress,
                    keyBuffer.count
                )
            }
        }
    }
    guard deriveStatus == kCCSuccess else { return nil }

    let input = Data(pkcs8)
    var encrypted = Data(count: input.count + kCCBlockSizeAES128)
    var encryptedCount = 0
    let encryptStatus = input.withUnsafeBytes { inputBuffer in
        encrypted.withUnsafeMutableBytes { outputBuffer in
            key.withUnsafeBufferPointer { keyBuffer in
                iv.withUnsafeBufferPointer { ivBuffer in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBuffer.baseAddress,
                        keyBuffer.count,
                        ivBuffer.baseAddress,
                        inputBuffer.baseAddress,
                        inputBuffer.count,
                        outputBuffer.baseAddress,
                        outputBuffer.count,
                        &encryptedCount
                    )
                }
            }
        }
    }
    key = [UInt8](repeating: 0, count: key.count)
    guard encryptStatus == kCCSuccess else { return nil }
    encrypted.count = encryptedCount

    let hmacSHA256 = derSequence([derOID([1, 2, 840, 113549, 2, 9]), derElement(0x05, [])])
    let pbkdf2Parameters = derSequence([derElement(0x04, salt), derInteger(iterations), derInteger(32), hmacSHA256])
    let pbkdf2Algorithm = derSequence([derOID([1, 2, 840, 113549, 1, 5, 12]), pbkdf2Parameters])
    let aesAlgorithm = derSequence([derOID([2, 16, 840, 1, 101, 3, 4, 1, 42]), derElement(0x04, iv)])
    let pbes2Parameters = derSequence([pbkdf2Algorithm, aesAlgorithm])
    let pbes2Algorithm = derSequence([derOID([1, 2, 840, 113549, 1, 5, 13]), pbes2Parameters])
    return derSequence([pbes2Algorithm, derElement(0x04, Array(encrypted))])
}

private func securityPKCS12Export(_ wire: [UInt8], password: String) -> [UInt8]? {
    guard wire.count >= 12, wire.count <= 16 * 1024 * 1024,
          Array(wire[0 ..< 4]) == [0x4b, 0x4a, 0x43, 0x31] else { return nil }
    var reader = SecurityWireReader(bytes: wire, offset: 4)
    guard reader.readUInt32() == 1, let entryCount = reader.readUInt32(), entryCount <= 1024 else { return nil }

    var bags: [[UInt8]] = []
    for _ in 0 ..< entryCount {
        guard let aliasBytes = reader.readField(maximumLength: 4096), !aliasBytes.isEmpty,
              let alias = String(bytes: aliasBytes, encoding: .utf8),
              let privateKey = reader.readField(maximumLength: 1024 * 1024), !privateKey.isEmpty,
              let certificateCount = reader.readUInt32(), certificateCount > 0, certificateCount <= 32 else { return nil }
        var certificates: [[UInt8]] = []
        var certificatePublicKeys: [[UInt8]] = []
        for _ in 0 ..< certificateCount {
            guard let certificate = reader.readField(maximumLength: 4 * 1024 * 1024), !certificate.isEmpty,
                  let publicKey = reader.readField(maximumLength: 1024 * 1024), !publicKey.isEmpty,
                  let secCertificate = SecCertificateCreateWithData(nil, Data(certificate) as CFData),
                  let secPublicKey = SecCertificateCopyKey(secCertificate) else { return nil }
            var error: Unmanaged<CFError>?
            guard let publicKeyData = SecKeyCopyExternalRepresentation(secPublicKey, &error) as Data? else {
                if let error { _ = error.takeRetainedValue() }
                return nil
            }
            guard wrapX509(Array(publicKeyData)) == publicKey else { return nil }
            certificates.append(certificate)
            certificatePublicKeys.append(publicKey)
        }
        guard let leaf = SecCertificateCreateWithData(nil, Data(certificates[0]) as CFData),
              let leafKey = SecCertificateCopyKey(leaf),
              let privateSecKey = securityKey(from: privateKey, isPrivate: true),
              let privatePublicKey = SecKeyCopyPublicKey(privateSecKey) else { return nil }
        var leafError: Unmanaged<CFError>?
        var privateError: Unmanaged<CFError>?
        guard let leafData = SecKeyCopyExternalRepresentation(leafKey, &leafError) as Data?,
              let privatePublicData = SecKeyCopyExternalRepresentation(privatePublicKey, &privateError) as Data?,
              leafData == privatePublicData else {
            if let leafError { _ = leafError.takeRetainedValue() }
            if let privateError { _ = privateError.takeRetainedValue() }
            return nil
        }
        guard let encryptedPrivateKey = securityEncryptPKCS8(privateKey, password: password) else { return nil }

        let keyID = Array(Insecure.SHA1.hash(data: leafData))
        let keyAttributes = derSet([
            securityPKCS12FriendlyName(alias),
            securityPKCS12LocalKeyID(keyID),
        ])
        let keyBag = derSequence([
            derOID([1, 2, 840, 113549, 1, 12, 10, 1, 2]),
            derElement(0xa0, encryptedPrivateKey),
            keyAttributes,
        ])
        bags.append(keyBag)

        for (index, certificate) in certificates.enumerated() {
            let certificateValue = derSequence([
                derOID([1, 2, 840, 113549, 1, 9, 22, 1]),
                derElement(0xa0, derElement(0x04, certificate)),
            ])
            let certificateAttributes = index == 0 ? keyAttributes : derSet([])
            bags.append(derSequence([
                derOID([1, 2, 840, 113549, 1, 12, 10, 1, 3]),
                derElement(0xa0, certificateValue),
                certificateAttributes,
            ]))
        }
    }
    guard reader.offset == wire.count else { return nil }

    let safeContents = derSequence(bags)
    let authenticatedSafe = derSequence([pkcs12ContentInfo(safeContents)])
    let authenticatedSafeContentInfo = pkcs12ContentInfo(authenticatedSafe)
    var salt = [UInt8](repeating: 0, count: 20)
    guard SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt) == errSecSuccess else { return nil }
    let passwordBytes: [UInt8] = Array(password.utf16).flatMap {
        [UInt8($0 >> 8), UInt8($0 & 0xff)]
    } + [0, 0]
    let macKey = securityPKCS12SHA1Key(
        password: passwordBytes,
        salt: salt,
        diversifier: 3,
        outputCount: 20,
        iterations: 2048
    )
    let mac = HMAC<Insecure.SHA1>.authenticationCode(
        for: Data(authenticatedSafe),
        using: SymmetricKey(data: Data(macKey))
    )
    let digestInfo = derSequence([
        derSequence([derOID([1, 3, 14, 3, 2, 26]), derElement(0x05, [])]),
        derElement(0x04, Array(mac)),
    ])
    let macData = derSequence([digestInfo, derElement(0x04, salt), derInteger(2048)])
    return derSequence([derInteger(3), authenticatedSafeContentInfo, macData])
}

private func securityPKCS12Aliases(_ bytes: [UInt8]) -> [String] {
    func children(_ bytes: [UInt8], in range: Range<Int>) -> [(tag: UInt8, payload: Range<Int>, end: Int)]? {
        var result: [(tag: UInt8, payload: Range<Int>, end: Int)] = []
        var offset = range.lowerBound
        while offset < range.upperBound {
            guard let element = readDERElement(bytes, at: offset), element.end <= range.upperBound else { return nil }
            result.append(element)
            offset = element.end
        }
        return offset == range.upperBound ? result : nil
    }
    func friendlyName(in attributes: [UInt8], range: Range<Int>) -> String? {
        guard let values = children(attributes, in: range) else { return nil }
        for attribute in values where attribute.tag == 0x30 {
            guard let fields = children(attributes, in: attribute.payload), fields.count == 2,
                  fields[0].tag == 0x06,
                  Array(attributes[fields[0].payload]) == [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x09, 0x14],
                  fields[1].tag == 0x31,
                  let value = readDERElement(attributes, at: fields[1].payload.lowerBound), value.tag == 0x1e else { continue }
            let nameBytes = Array(attributes[value.payload])
            guard nameBytes.count % 2 == 0 else { continue }
            let units = stride(from: 0, to: nameBytes.count, by: 2).map {
                UInt16(nameBytes[$0]) << 8 | UInt16(nameBytes[$0 + 1])
            }
            return String(decoding: units, as: UTF16.self)
        }
        return nil
    }

    guard let pfx = readDERElement(bytes, at: 0), pfx.tag == 0x30,
          let pfxFields = children(bytes, in: pfx.payload), pfxFields.count >= 2,
          let authSafeFields = children(bytes, in: pfxFields[1].payload), authSafeFields.count == 2,
          authSafeFields[1].tag == 0xa0,
          let explicitOctets = readDERElement(bytes, at: authSafeFields[1].payload.lowerBound), explicitOctets.tag == 0x04 else { return [] }
    let authenticatedSafe = Array(bytes[explicitOctets.payload])
    guard let safeSequence = readDERElement(authenticatedSafe, at: 0), safeSequence.tag == 0x30,
          let contentInfos = children(authenticatedSafe, in: safeSequence.payload) else { return [] }
    var result: [String] = []
    let dataOID: [UInt8] = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x01]
    let shroudedKeyBagOID: [UInt8] = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x0c, 0x0a, 0x01, 0x02]
    let keyBagOID: [UInt8] = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x0c, 0x0a, 0x01, 0x01]
    for contentInfo in contentInfos {
        guard let fields = children(authenticatedSafe, in: contentInfo.payload), fields.count == 2,
              fields[0].tag == 0x06, Array(authenticatedSafe[fields[0].payload]) == dataOID,
              fields[1].tag == 0xa0,
              let octets = readDERElement(authenticatedSafe, at: fields[1].payload.lowerBound), octets.tag == 0x04 else { continue }
        let safeContents = Array(authenticatedSafe[octets.payload])
        guard let bagsSequence = readDERElement(safeContents, at: 0), bagsSequence.tag == 0x30,
              let bags = children(safeContents, in: bagsSequence.payload) else { continue }
        for bag in bags {
            guard let bagFields = children(safeContents, in: bag.payload), bagFields.count >= 2,
                  bagFields[0].tag == 0x06 else { continue }
            let bagOID = Array(safeContents[bagFields[0].payload])
            guard bagOID == shroudedKeyBagOID || bagOID == keyBagOID,
                  bagFields.count >= 3, let name = friendlyName(in: safeContents, range: bagFields[2].payload) else { continue }
            result.append(name)
        }
    }
    return result
}

private enum SecurityPKCS12Hash {
    case sha1
    case sha256

    var digestLength: Int { self == .sha1 ? 20 : 32 }

    func hash(_ bytes: [UInt8]) -> [UInt8] {
        switch self {
        case .sha1: return Array(Insecure.SHA1.hash(data: Data(bytes)))
        case .sha256: return Array(SHA256.hash(data: Data(bytes)))
        }
    }

    func hmac(_ bytes: [UInt8], key: [UInt8]) -> [UInt8] {
        let symmetricKey = SymmetricKey(data: Data(key))
        switch self {
        case .sha1: return Array(HMAC<Insecure.SHA1>.authenticationCode(for: Data(bytes), using: symmetricKey))
        case .sha256: return Array(HMAC<SHA256>.authenticationCode(for: Data(bytes), using: symmetricKey))
        }
    }
}

private struct SecurityPKCS12KeyEntry {
    let alias: String
    let encodedKey: [UInt8]
    let localKeyID: [UInt8]?
}

private struct SecurityPKCS12Certificate {
    let encoded: [UInt8]
    let localKeyID: [UInt8]?
}

private func securityDERChildren(
    _ bytes: [UInt8],
    in range: Range<Int>
) -> [(tag: UInt8, payload: Range<Int>, end: Int)]? {
    var result: [(tag: UInt8, payload: Range<Int>, end: Int)] = []
    var offset = range.lowerBound
    while offset < range.upperBound {
        guard let element = readDERElement(bytes, at: offset), element.end <= range.upperBound else { return nil }
        result.append(element)
        offset = element.end
    }
    return offset == range.upperBound ? result : nil
}

private func securityDERInteger(_ bytes: [UInt8], element: (tag: UInt8, payload: Range<Int>, end: Int)) -> Int? {
    guard element.tag == 0x02, element.payload.count > 0, element.payload.count <= 4,
          bytes[element.payload.lowerBound] & 0x80 == 0 else { return nil }
    return bytes[element.payload].reduce(0) { ($0 << 8) | Int($1) }
}

private func securityDEROctets(_ bytes: [UInt8], element: (tag: UInt8, payload: Range<Int>, end: Int)) -> [UInt8]? {
    if element.tag == 0x04 || element.tag == 0x80 { return Array(bytes[element.payload]) }
    guard element.tag == 0xa0,
          let children = securityDERChildren(bytes, in: element.payload) else { return nil }
    var result: [UInt8] = []
    for child in children {
        guard child.tag == 0x04 || child.tag == 0x80 else { return nil }
        result.append(contentsOf: bytes[child.payload])
    }
    return result
}

private func securityPKCS12KDF(
    hash: SecurityPKCS12Hash,
    password: [UInt8],
    salt: [UInt8],
    diversifier: UInt8,
    outputCount: Int,
    iterations: Int
) -> [UInt8] {
    let blockSize = 64
    let diversifierBytes = [UInt8](repeating: diversifier, count: blockSize)
    var state = securityExpandPKCS12Block(salt, width: blockSize)
        + securityExpandPKCS12Block(password, width: blockSize)
    var output: [UInt8] = []
    while output.count < outputCount {
        var digest = hash.hash(diversifierBytes + state)
        if iterations > 1 {
            for _ in 1 ..< iterations { digest = hash.hash(digest) }
        }
        output.append(contentsOf: digest)
        let adjustment = (0 ..< blockSize).map { digest[$0 % digest.count] }
        if !state.isEmpty {
            for start in stride(from: 0, to: state.count, by: blockSize) {
                var carry = 1
                for index in stride(from: start + blockSize - 1, through: start, by: -1) {
                    let sum = Int(state[index]) + Int(adjustment[index - start]) + carry
                    state[index] = UInt8(sum & 0xff)
                    carry = sum >> 8
                }
            }
        }
    }
    return Array(output.prefix(outputCount))
}

private func securityPBKDF2(
    password: [UInt8],
    salt: [UInt8],
    iterations: Int,
    outputCount: Int,
    prf: CCPseudoRandomAlgorithm
) -> [UInt8]? {
    guard iterations > 0, iterations <= 1_000_000, outputCount > 0, outputCount <= 64 else { return nil }
    var output = [UInt8](repeating: 0, count: outputCount)
    let status = password.withUnsafeBufferPointer { passwordBuffer in
        salt.withUnsafeBufferPointer { saltBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBuffer.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: Int8.self) },
                    passwordBuffer.count,
                    saltBuffer.baseAddress,
                    saltBuffer.count,
                    prf,
                    UInt32(iterations),
                    outputBuffer.baseAddress,
                    outputBuffer.count
                )
            }
        }
    }
    return status == kCCSuccess ? output : nil
}

private func securityCCCrypt(
    operation: CCOperation,
    algorithm: CCAlgorithm,
    options: CCOptions,
    key: [UInt8],
    iv: [UInt8]?,
    input: [UInt8]
) -> [UInt8]? {
    var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
    var outputCount = 0
    let status = input.withUnsafeBufferPointer { inputBuffer in
        output.withUnsafeMutableBufferPointer { outputBuffer in
            key.withUnsafeBufferPointer { keyBuffer in
                if let iv {
                    return iv.withUnsafeBufferPointer { ivBuffer in
                        CCCrypt(
                            operation,
                            algorithm,
                            options,
                            keyBuffer.baseAddress,
                            keyBuffer.count,
                            ivBuffer.baseAddress,
                            inputBuffer.baseAddress,
                            inputBuffer.count,
                            outputBuffer.baseAddress,
                            outputBuffer.count,
                            &outputCount
                        )
                    }
                }
                return CCCrypt(
                    operation,
                    algorithm,
                    options,
                    keyBuffer.baseAddress,
                    keyBuffer.count,
                    nil,
                    inputBuffer.baseAddress,
                    inputBuffer.count,
                    outputBuffer.baseAddress,
                    outputBuffer.count,
                    &outputCount
                )
            }
        }
    }
    guard status == kCCSuccess else { return nil }
    return Array(output.prefix(outputCount))
}

private func securityPKCS12Decrypt(
    algorithmIdentifier: [UInt8],
    encrypted: [UInt8],
    password: String
) -> [UInt8]? {
    guard let algorithmElement = readDERElement(algorithmIdentifier, at: 0), algorithmElement.tag == 0x30,
          let fields = securityDERChildren(algorithmIdentifier, in: algorithmElement.payload), fields.count == 2,
          fields[0].tag == 0x06,
          let parameters = readDERElement(algorithmIdentifier, at: fields[1].payload.lowerBound),
          parameters.tag == 0x30,
          let parameterFields = securityDERChildren(algorithmIdentifier, in: parameters.payload) else { return nil }
    let algorithmOID = Array(algorithmIdentifier[fields[0].payload])
    if algorithmOID == [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x05, 0x0d] {
        guard parameterFields.count == 2,
              let kdfFields = securityDERChildren(algorithmIdentifier, in: parameterFields[0].payload),
              kdfFields.count == 2, kdfFields[0].tag == 0x06,
              Array(algorithmIdentifier[kdfFields[0].payload]) == [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x05, 0x0c],
              let kdfParams = readDERElement(algorithmIdentifier, at: kdfFields[1].payload.lowerBound),
              let kdfParamFields = securityDERChildren(algorithmIdentifier, in: kdfParams.payload),
              kdfParamFields.count >= 2, kdfParamFields[0].tag == 0x04,
              let iterations = securityDERInteger(algorithmIdentifier, element: kdfParamFields[1]),
              let cipherFields = securityDERChildren(algorithmIdentifier, in: parameterFields[1].payload),
              cipherFields.count == 2, cipherFields[0].tag == 0x06,
              let iv = securityDEROctets(algorithmIdentifier, element: cipherFields[1]),
              iv.count == 16 else { return nil }
        let cipherOID = Array(algorithmIdentifier[cipherFields[0].payload])
        let keySize: Int
        switch cipherOID {
        case [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x01, 0x02]: keySize = 16
        case [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x01, 0x16]: keySize = 24
        case [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x01, 0x2a]: keySize = 32
        default: return nil
        }
        let passwordBytes = Array(password.utf8)
        let keyLength: Int
        let prf: CCPseudoRandomAlgorithm
        if kdfParamFields.count > 2, kdfParamFields[2].tag == 0x02 {
            guard let parsedLength = securityDERInteger(algorithmIdentifier, element: kdfParamFields[2]) else { return nil }
            keyLength = parsedLength
        } else {
            keyLength = keySize
        }
        if keyLength != keySize { return nil }
        if kdfParamFields.count > 3 {
            guard let prfFields = securityDERChildren(algorithmIdentifier, in: kdfParamFields[3].payload),
                  let prfOIDField = prfFields.first, prfOIDField.tag == 0x06 else { return nil }
            switch Array(algorithmIdentifier[prfOIDField.payload]) {
            case [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x02, 0x07]: prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
            case [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x02, 0x09]: prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256)
            case [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x02, 0x0a]: prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA384)
            case [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x02, 0x0b]: prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512)
            default: return nil
            }
        } else {
            prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
        }
        guard let key = securityPBKDF2(password: passwordBytes, salt: Array(algorithmIdentifier[kdfParamFields[0].payload]),
                                        iterations: iterations, outputCount: keySize, prf: prf) else { return nil }
        return securityCCCrypt(
            operation: CCOperation(kCCDecrypt), algorithm: CCAlgorithm(kCCAlgorithmAES),
            options: CCOptions(kCCOptionPKCS7Padding), key: key, iv: iv, input: encrypted
        )
    }

    var passwordEncoding: [UInt8] = []
    for character in password.utf16 {
        passwordEncoding.append(UInt8(character >> 8))
        passwordEncoding.append(UInt8(character & 0xff))
    }
    passwordEncoding += [0, 0]
    guard parameterFields.count == 2, parameterFields[0].tag == 0x04,
          let iterations = securityDERInteger(algorithmIdentifier, element: parameterFields[1]),
          iterations > 0, iterations <= 1_000_000 else { return nil }
    let salt = Array(algorithmIdentifier[parameterFields[0].payload])
    let keyOID = algorithmOID
    let keySize: Int
    let algorithm: CCAlgorithm
    let ivSize: Int
    switch keyOID {
    case [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x0c, 0x01, 0x01]:
        keySize = 16; algorithm = CCAlgorithm(kCCAlgorithmRC4); ivSize = 0
    case [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x0c, 0x01, 0x02]:
        keySize = 5; algorithm = CCAlgorithm(kCCAlgorithmRC4); ivSize = 0
    case [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x0c, 0x01, 0x03]:
        keySize = 24; algorithm = CCAlgorithm(kCCAlgorithm3DES); ivSize = 8
    case [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x0c, 0x01, 0x04]:
        keySize = 16; algorithm = CCAlgorithm(kCCAlgorithm3DES); ivSize = 8
    case [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x0c, 0x01, 0x05]:
        keySize = 16; algorithm = CCAlgorithm(kCCAlgorithmRC2); ivSize = 8
    case [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x0c, 0x01, 0x06]:
        keySize = 5; algorithm = CCAlgorithm(kCCAlgorithmRC2); ivSize = 8
    default: return nil
    }
    let key = securityPKCS12KDF(
        hash: .sha1, password: passwordEncoding, salt: salt, diversifier: 1,
        outputCount: keySize, iterations: iterations
    )
    let iv = ivSize == 0 ? nil : securityPKCS12KDF(
        hash: .sha1, password: passwordEncoding, salt: salt, diversifier: 2,
        outputCount: ivSize, iterations: iterations
    )
    let adjustedKey = keyOID == [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x0c, 0x01, 0x04]
        ? key + Array(key.prefix(8)) : key
    let options: CCOptions = algorithm == CCAlgorithm(kCCAlgorithmRC4) ? 0 : CCOptions(kCCOptionPKCS7Padding)
    return securityCCCrypt(
        operation: CCOperation(kCCDecrypt), algorithm: algorithm, options: options,
        key: adjustedKey, iv: iv, input: encrypted
    )
}

private func securityPKCS12AttributeValues(_ bytes: [UInt8], element: (tag: UInt8, payload: Range<Int>, end: Int)) -> (alias: String?, localKeyID: [UInt8]?) {
    guard element.tag == 0x31,
          let attributes = securityDERChildren(bytes, in: element.payload) else { return (nil, nil) }
    var alias: String?
    var localKeyID: [UInt8]?
    for attribute in attributes where attribute.tag == 0x30 {
        guard let fields = securityDERChildren(bytes, in: attribute.payload), fields.count == 2,
              fields[0].tag == 0x06, fields[1].tag == 0x31,
              let value = readDERElement(bytes, at: fields[1].payload.lowerBound) else { continue }
        let oid = Array(bytes[fields[0].payload])
        if oid == [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x09, 0x14], value.tag == 0x1e {
            let nameBytes = Array(bytes[value.payload])
            if nameBytes.count % 2 == 0 {
                let units = stride(from: 0, to: nameBytes.count, by: 2).map {
                    UInt16(nameBytes[$0]) << 8 | UInt16(nameBytes[$0 + 1])
                }
                alias = String(decoding: units, as: UTF16.self)
            }
        } else if oid == [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x09, 0x15], value.tag == 0x04 {
            localKeyID = Array(bytes[value.payload])
        }
    }
    return (alias, localKeyID)
}

private func securityPKCS12SafeContents(_ bytes: [UInt8], password: String) -> ([SecurityPKCS12KeyEntry], [SecurityPKCS12Certificate])? {
    guard let sequence = readDERElement(bytes, at: 0), sequence.tag == 0x30,
          sequence.end == bytes.count,
          let bags = securityDERChildren(bytes, in: sequence.payload) else { return nil }
    let keyBagOID = [UInt8]([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x0c, 0x0a, 0x01, 0x01])
    let shroudedKeyBagOID = [UInt8]([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x0c, 0x0a, 0x01, 0x02])
    let certificateBagOID = [UInt8]([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x0c, 0x0a, 0x01, 0x03])
    let x509CertificateOID = [UInt8]([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x09, 0x16, 0x01])
    var keys: [SecurityPKCS12KeyEntry] = []
    var certificates: [SecurityPKCS12Certificate] = []
    for bag in bags where bag.tag == 0x30 {
        guard let fields = securityDERChildren(bytes, in: bag.payload), fields.count >= 2,
              fields[0].tag == 0x06, fields[1].tag == 0xa0,
              let bagValue = readDERElement(bytes, at: fields[1].payload.lowerBound) else { return nil }
        let oid = Array(bytes[fields[0].payload])
        var attributes: (alias: String?, localKeyID: [UInt8]?) = (nil, nil)
        if fields.count > 2 { attributes = securityPKCS12AttributeValues(bytes, element: fields[2]) }
        if oid == keyBagOID {
            keys.append(SecurityPKCS12KeyEntry(
                alias: attributes.alias ?? "key-\(keys.count + 1)",
                encodedKey: Array(bytes[bagValue.payload.lowerBound ..< bagValue.end]),
                localKeyID: attributes.localKeyID
            ))
        } else if oid == shroudedKeyBagOID {
            guard bagValue.tag == 0x30,
                  let encryptedFields = securityDERChildren(bytes, in: bagValue.payload), encryptedFields.count == 2,
                  let encrypted = securityDEROctets(bytes, element: encryptedFields[1]),
                  let encodedKey = securityPKCS12Decrypt(
                    algorithmIdentifier: Array(bytes[encryptedFields[0].payload.lowerBound ..< encryptedFields[0].end]),
                    encrypted: encrypted,
                    password: password
                  ) else { return nil }
            keys.append(SecurityPKCS12KeyEntry(
                alias: attributes.alias ?? "key-\(keys.count + 1)",
                encodedKey: encodedKey,
                localKeyID: attributes.localKeyID
            ))
        } else if oid == certificateBagOID {
            guard bagValue.tag == 0x30,
                  let certificateFields = securityDERChildren(bytes, in: bagValue.payload),
                  certificateFields.count == 2, certificateFields[0].tag == 0x06,
                  Array(bytes[certificateFields[0].payload]) == x509CertificateOID,
                  certificateFields[1].tag == 0xa0,
                  let certificateOctets = readDERElement(bytes, at: certificateFields[1].payload.lowerBound),
                  let encoded = securityDEROctets(bytes, element: certificateOctets) else { return nil }
            certificates.append(SecurityPKCS12Certificate(encoded: encoded, localKeyID: attributes.localKeyID))
        }
    }
    return (keys, certificates)
}

private func securityPKCS12DecodeWire(_ bytes: [UInt8], password: String) -> [UInt8]? {
    guard bytes.count <= 16 * 1024 * 1024,
          let pfx = readDERElement(bytes, at: 0), pfx.tag == 0x30, pfx.end == bytes.count,
          let pfxFields = securityDERChildren(bytes, in: pfx.payload), pfxFields.count >= 3,
          securityDERInteger(bytes, element: pfxFields[0]) == 3,
          let authSafeFields = securityDERChildren(bytes, in: pfxFields[1].payload), authSafeFields.count == 2,
          authSafeFields[0].tag == 0x06,
          Array(bytes[authSafeFields[0].payload]) == [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x01],
          authSafeFields[1].tag == 0xa0,
          let authenticatedSafeOctets = readDERElement(bytes, at: authSafeFields[1].payload.lowerBound),
          let authenticatedSafe = securityDEROctets(bytes, element: authenticatedSafeOctets),
          let macFields = securityDERChildren(bytes, in: pfxFields[2].payload), macFields.count >= 2,
          let digestInfo = securityDERChildren(bytes, in: macFields[0].payload), digestInfo.count == 2,
          let digestAlgorithm = securityDERChildren(bytes, in: digestInfo[0].payload),
          let digestOID = digestAlgorithm.first, digestOID.tag == 0x06,
          let expectedMAC = securityDEROctets(bytes, element: digestInfo[1]),
          let salt = securityDEROctets(bytes, element: macFields[1]) else { return nil }

    let hash: SecurityPKCS12Hash
    switch Array(bytes[digestOID.payload]) {
    case [0x2b, 0x0e, 0x03, 0x02, 0x1a]: hash = .sha1
    case [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]: hash = .sha256
    default: return nil
    }
    let iterations = macFields.count > 2 ? (securityDERInteger(bytes, element: macFields[2]) ?? 0) : 1
    guard iterations > 0, iterations <= 1_000_000, expectedMAC.count == hash.digestLength else { return nil }
    let passwordBytes: [UInt8] = Array(password.utf16).flatMap { [UInt8($0 >> 8), UInt8($0 & 0xff)] } + [0, 0]
    let macKey = securityPKCS12KDF(
        hash: hash, password: passwordBytes, salt: salt, diversifier: 3,
        outputCount: hash.digestLength, iterations: iterations
    )
    let actualMAC = hash.hmac(authenticatedSafe, key: macKey)
    var mismatch: UInt8 = 0
    for (left, right) in zip(actualMAC, expectedMAC) { mismatch |= left ^ right }
    guard mismatch == 0 else { return nil }

    guard let safeSequence = readDERElement(authenticatedSafe, at: 0), safeSequence.tag == 0x30,
          let contentInfos = securityDERChildren(authenticatedSafe, in: safeSequence.payload) else { return nil }
    let dataOID: [UInt8] = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x01]
    let encryptedDataOID: [UInt8] = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x06]
    var keys: [SecurityPKCS12KeyEntry] = []
    var certificates: [SecurityPKCS12Certificate] = []
    for contentInfo in contentInfos {
        guard let fields = securityDERChildren(authenticatedSafe, in: contentInfo.payload), fields.count == 2,
              fields[0].tag == 0x06, fields[1].tag == 0xa0,
              let content = readDERElement(authenticatedSafe, at: fields[1].payload.lowerBound) else { return nil }
        let contentOID = Array(authenticatedSafe[fields[0].payload])
        let safeContents: [UInt8]
        if contentOID == dataOID {
            guard let decoded = securityDEROctets(authenticatedSafe, element: content) else { return nil }
            safeContents = decoded
        } else if contentOID == encryptedDataOID {
            guard content.tag == 0x30,
                  let encryptedDataFields = securityDERChildren(authenticatedSafe, in: content.payload),
                  encryptedDataFields.count == 2,
                  let encryptedContentInfo = securityDERChildren(authenticatedSafe, in: encryptedDataFields[1].payload),
                  encryptedContentInfo.count == 3,
                  encryptedContentInfo[1].tag == 0x30,
                  let encrypted = securityDEROctets(authenticatedSafe, element: encryptedContentInfo[2]),
                  let decrypted = securityPKCS12Decrypt(
                    algorithmIdentifier: Array(authenticatedSafe[encryptedContentInfo[1].payload.lowerBound ..< encryptedContentInfo[1].end]),
                    encrypted: encrypted,
                    password: password
                  ) else { return nil }
            safeContents = decrypted
        } else {
            continue
        }
        guard let parsed = securityPKCS12SafeContents(safeContents, password: password) else { return nil }
        keys.append(contentsOf: parsed.0)
        certificates.append(contentsOf: parsed.1)
    }
    guard keys.count <= 1024 else { return nil }
    if keys.isEmpty {
        guard certificates.isEmpty else { return nil }
        var emptyWire: [UInt8] = [0x4b, 0x4a, 0x43, 0x31]
        guard appendSecurityUInt32(1, to: &emptyWire), appendSecurityUInt32(0, to: &emptyWire) else { return nil }
        return emptyWire
    }
    guard !certificates.isEmpty else { return nil }

    var wire: [UInt8] = [0x4b, 0x4a, 0x43, 0x31]
    guard appendSecurityUInt32(1, to: &wire), appendSecurityUInt32(keys.count, to: &wire) else { return nil }
    for key in keys {
        guard let privateSecKey = securityKey(from: key.encodedKey, isPrivate: true),
              let privatePublicKey = SecKeyCopyPublicKey(privateSecKey) else { return nil }
        var privateError: Unmanaged<CFError>?
        guard let privatePublicData = SecKeyCopyExternalRepresentation(privatePublicKey, &privateError) as Data? else {
            if let privateError { _ = privateError.takeRetainedValue() }
            return nil
        }
        var encodedCertificates: [(certificate: [UInt8], publicKey: [UInt8], localKeyID: [UInt8]?)] = []
        for certificate in certificates {
            guard let secCertificate = SecCertificateCreateWithData(nil, Data(certificate.encoded) as CFData),
                  let publicKey = SecCertificateCopyKey(secCertificate) else { return nil }
            var certificateError: Unmanaged<CFError>?
            guard let publicData = SecKeyCopyExternalRepresentation(publicKey, &certificateError) as Data? else {
                if let certificateError { _ = certificateError.takeRetainedValue() }
                return nil
            }
            encodedCertificates.append((certificate.encoded, wrapX509(Array(publicData)), certificate.localKeyID))
        }
        guard let leafIndex = encodedCertificates.firstIndex(where: { $0.publicKey == wrapX509(Array(privatePublicData)) }) else { return nil }
        let matching = key.localKeyID.map { id in
            encodedCertificates.enumerated().filter { $0.element.localKeyID == id }
        } ?? []
        let unmarked = encodedCertificates.enumerated().filter { $0.element.localKeyID == nil }
        var chain = [encodedCertificates[leafIndex]]
        chain.append(contentsOf: matching.filter { $0.offset != leafIndex }.map(\.element))
        chain.append(contentsOf: unmarked.filter { $0.offset != leafIndex }.map(\.element))
        guard !chain.isEmpty,
              appendSecurityField(Array(key.alias.utf8), to: &wire),
              appendSecurityField(key.encodedKey, to: &wire),
              appendSecurityUInt32(chain.count, to: &wire) else { return nil }
        for certificate in chain {
            guard appendSecurityField(certificate.certificate, to: &wire),
                  appendSecurityField(certificate.publicKey, to: &wire) else { return nil }
        }
    }
    return wire.count <= 16 * 1024 * 1024 ? wire : nil
}
#endif

#if canImport(Security)
private func securitySignatureAlgorithm(_ raw: Int) -> SecKeyAlgorithm? {
    guard let name = runtimeStringFromRaw(raw) else { return nil }
    let normalized = name.uppercased().replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "")
    switch normalized {
    case "SHA1WITHRSA": return .rsaSignatureMessagePKCS1v15SHA1
    case "SHA256WITHRSA": return .rsaSignatureMessagePKCS1v15SHA256
    case "SHA384WITHRSA": return .rsaSignatureMessagePKCS1v15SHA384
    case "SHA512WITHRSA": return .rsaSignatureMessagePKCS1v15SHA512
    default: return nil
    }
}

private func securityKey(from encoded: [UInt8], isPrivate: Bool) -> SecKey? {
    let keyBytes = isPrivate ? unwrapPKCS8(encoded) : unwrapX509(encoded)
    guard let keyBytes else { return nil }
    let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass as String: isPrivate ? kSecAttrKeyClassPrivate : kSecAttrKeyClassPublic,
    ]
    var error: Unmanaged<CFError>?
    let key = SecKeyCreateWithData(Data(keyBytes) as CFData, attributes as CFDictionary, &error)
    if let error { _ = error.takeRetainedValue() }
    return key
}
#endif

@_cdecl("__kk_security_rsa_generate_key_pair")
public func __kk_security_rsa_generate_key_pair(
    _ keySize: Int,
    _ privateOutputRaw: Int,
    _ publicOutputRaw: Int
) -> Int {
    #if canImport(Security)
    guard keySize >= 512, keySize <= 16384, keySize % 64 == 0 else { return -1 }
    let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeySizeInBits as String: keySize,
        kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: false],
    ]
    var error: Unmanaged<CFError>?
    guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
        if let error { _ = error.takeRetainedValue() }
        return -1
    }
    guard let publicKey = SecKeyCopyPublicKey(privateKey) else { return -1 }
    var privateError: Unmanaged<CFError>?
    var publicError: Unmanaged<CFError>?
    guard let privateData = SecKeyCopyExternalRepresentation(privateKey, &privateError) as Data?,
          let publicData = SecKeyCopyExternalRepresentation(publicKey, &publicError) as Data? else {
        if let privateError { _ = privateError.takeRetainedValue() }
        if let publicError { _ = publicError.takeRetainedValue() }
        return -1
    }
    let privateEncoding = wrapPKCS8(Array(privateData))
    let publicEncoding = wrapX509(Array(publicData))
    guard runtimeSecurityWrite(privateEncoding, to: privateOutputRaw),
          runtimeSecurityWrite(publicEncoding, to: publicOutputRaw) else { return -1 }
    let packedLengths = (UInt64(publicEncoding.count) << 32) | UInt64(privateEncoding.count)
    return Int(bitPattern: UInt(packedLengths))
    #else
    return -1
    #endif
}

@_cdecl("__kk_security_rsa_sign")
public func __kk_security_rsa_sign(
    _ algorithmRaw: Int,
    _ privateKeyRaw: Int,
    _ dataRaw: Int,
    _ outputRaw: Int
) -> Int {
    #if canImport(Security)
    guard let algorithm = securitySignatureAlgorithm(algorithmRaw),
          let privateBytes = runtimeSecurityBytes(from: privateKeyRaw),
          let input = runtimeSecurityBytes(from: dataRaw),
          let key = securityKey(from: privateBytes, isPrivate: true),
          SecKeyIsAlgorithmSupported(key, .sign, algorithm) else { return -1 }
    var error: Unmanaged<CFError>?
    guard let signature = SecKeyCreateSignature(key, algorithm, Data(input) as CFData, &error) else {
        if let error { _ = error.takeRetainedValue() }
        return -1
    }
    let bytes = Array(signature as Data)
    guard runtimeSecurityWrite(bytes, to: outputRaw) else { return -1 }
    return bytes.count
    #else
    return -1
    #endif
}

@_cdecl("__kk_security_rsa_verify")
public func __kk_security_rsa_verify(
    _ algorithmRaw: Int,
    _ publicKeyRaw: Int,
    _ dataRaw: Int,
    _ signatureRaw: Int
) -> Int {
    #if canImport(Security)
    guard let algorithm = securitySignatureAlgorithm(algorithmRaw),
          let publicBytes = runtimeSecurityBytes(from: publicKeyRaw),
          let input = runtimeSecurityBytes(from: dataRaw),
          let signature = runtimeSecurityBytes(from: signatureRaw),
          let key = securityKey(from: publicBytes, isPrivate: false),
          SecKeyIsAlgorithmSupported(key, .verify, algorithm) else { return -1 }
    var error: Unmanaged<CFError>?
    let valid = SecKeyVerifySignature(key, algorithm, Data(input) as CFData, Data(signature) as CFData, &error)
    if let error { _ = error.takeRetainedValue() }
    return valid ? 1 : 0
    #else
    return -1
    #endif
}

@_cdecl("__kk_security_pkcs12_load")
public func __kk_security_pkcs12_load(
    _ inputRaw: Int,
    _ passwordRaw: Int,
    _ outputRaw: Int
) -> Int {
    #if canImport(Security)
    guard let input = runtimeSecurityBytes(from: inputRaw), input.count <= 16 * 1024 * 1024,
          let password = runtimeStringFromRaw(passwordRaw) else { return -1 }
    if let wire = securityPKCS12DecodeWire(input, password: password),
       wire.count <= 16 * 1024 * 1024, runtimeSecurityWrite(wire, to: outputRaw) {
        return wire.count
    }
    guard #available(macOS 15.0, *) else { return -1 }

    let options: [String: Any] = [
        kSecImportExportPassphrase as String: password,
        kSecImportToMemoryOnly as String: true,
    ]
    var importedItems: CFArray?
    let status = SecPKCS12Import(Data(input) as CFData, options as CFDictionary, &importedItems)
    guard status == errSecSuccess, let importedItems else { return -1 }

    let aliases = securityPKCS12Aliases(input)
    var entries: [(alias: [UInt8], privateKey: [UInt8], certificates: [([UInt8], [UInt8])])] = []
    for (index, item) in (importedItems as [AnyObject]).enumerated() {
        guard let dictionary = item as? [String: Any],
              let identityValue = dictionary[kSecImportItemIdentity as String] else { continue }
        let identity = identityValue as! SecIdentity
        var privateKeyValue: SecKey?
        guard SecIdentityCopyPrivateKey(identity, &privateKeyValue) == errSecSuccess,
              let privateKey = privateKeyValue,
              let chainValue = dictionary[kSecImportItemCertChain as String] else { return -1 }
        let chain = (chainValue as! [AnyObject]).map { $0 as! SecCertificate }
        guard !chain.isEmpty else { return -1 }
        var privateError: Unmanaged<CFError>?
        guard let privateData = SecKeyCopyExternalRepresentation(privateKey, &privateError) as Data? else {
            if let privateError { _ = privateError.takeRetainedValue() }
            return -1
        }
        let privateEncoding = wrapPKCS8(Array(privateData))
        var encodedCertificates: [([UInt8], [UInt8])] = []
        for certificate in chain {
            guard let publicKey = SecCertificateCopyKey(certificate) else { return -1 }
            var publicError: Unmanaged<CFError>?
            guard let publicData = SecKeyCopyExternalRepresentation(publicKey, &publicError) as Data? else {
                if let publicError { _ = publicError.takeRetainedValue() }
                return -1
            }
            encodedCertificates.append((Array(SecCertificateCopyData(certificate) as Data), wrapX509(Array(publicData))))
        }
        let alias = dictionary[kSecImportItemLabel as String] as? String
            ?? (index < aliases.count ? aliases[index] : "key-\(index + 1)")
        entries.append((Array(alias.utf8), privateEncoding, encodedCertificates))
    }
    guard entries.count <= 1024 else { return -1 }

    var wire: [UInt8] = [0x4b, 0x4a, 0x43, 0x31]
    guard appendSecurityUInt32(1, to: &wire), appendSecurityUInt32(entries.count, to: &wire) else { return -1 }
    for entry in entries {
        guard appendSecurityField(entry.alias, to: &wire), appendSecurityField(entry.privateKey, to: &wire),
              appendSecurityUInt32(entry.certificates.count, to: &wire) else { return -1 }
        for (certificate, publicKey) in entry.certificates {
            guard appendSecurityField(certificate, to: &wire), appendSecurityField(publicKey, to: &wire) else { return -1 }
        }
    }
    guard wire.count <= 16 * 1024 * 1024, runtimeSecurityWrite(wire, to: outputRaw) else { return -1 }
    return wire.count
    #else
    return -1
    #endif
}

@_cdecl("__kk_security_pkcs12_store")
public func __kk_security_pkcs12_store(
    _ passwordRaw: Int,
    _ wireRaw: Int,
    _ outputRaw: Int
) -> Int {
    #if canImport(Security)
    guard let password = runtimeStringFromRaw(passwordRaw),
          let wire = runtimeSecurityBytes(from: wireRaw),
          let pfx = securityPKCS12Export(wire, password: password),
          pfx.count <= 16 * 1024 * 1024,
          runtimeSecurityWrite(pfx, to: outputRaw) else { return -1 }
    return pfx.count
    #else
    return -1
    #endif
}

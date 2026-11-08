import Foundation
#if canImport(Security)
import Security
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

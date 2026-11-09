private let abi = RuntimeABISectionBuilder("Security")

public extension RuntimeABISpec {
    static let securityFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_security_rsa_generate_key_pair", "keySize privateOutput publicOutput"),
        abi.nt("__kk_security_rsa_sign", "algorithm privateKey data output"),
        abi.nt("__kk_security_rsa_verify", "algorithm publicKey data signature"),
        abi.nt("__kk_security_pkcs12_load", "input password output"),
        abi.nt("__kk_security_pkcs12_store", "password input output"),
    ]
}

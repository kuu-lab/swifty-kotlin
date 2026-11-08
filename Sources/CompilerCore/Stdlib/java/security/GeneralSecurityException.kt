package java.security

public open class GeneralSecurityException : java.lang.Exception {
    public constructor() : super()

    public constructor(message: String?) : super(message)

    public constructor(message: String?, cause: Throwable?) : super(message, cause)

    public constructor(cause: Throwable?) : super(cause)
}

public open class InvalidKeyException : GeneralSecurityException {
    public constructor() : super()

    public constructor(message: String?) : super(message)
}

public open class InvalidAlgorithmParameterException : GeneralSecurityException {
    public constructor() : super()

    public constructor(message: String?) : super(message)
}

public open class SignatureException : GeneralSecurityException {
    public constructor() : super()

    public constructor(message: String?) : super(message)

    public constructor(message: String?, cause: Throwable?) : super(message, cause)
}

public open class KeyStoreException : GeneralSecurityException {
    public constructor() : super()

    public constructor(message: String?) : super(message)
}

public open class UnrecoverableKeyException : GeneralSecurityException {
    public constructor() : super()

    public constructor(message: String?) : super(message)
}

public open class NoSuchProviderException : GeneralSecurityException {
    public constructor() : super()

    public constructor(message: String?) : super(message)
}

public open class ProviderException : java.lang.RuntimeException {
    public constructor(message: String?) : super(message)

    public constructor(message: String?, cause: Throwable?) : super(message, cause)
}

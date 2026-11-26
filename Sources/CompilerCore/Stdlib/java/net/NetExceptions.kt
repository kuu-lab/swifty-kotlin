package java.net

import java.io.IOException

public open class SocketException : IOException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

public open class UnknownHostException : IOException {
    public constructor() : super()
    public constructor(host: String?) : super(host)
}

public open class ConnectException : SocketException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

public open class BindException : SocketException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

public open class MalformedURLException : IOException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

public open class SocketTimeoutException : InterruptedIOException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

public open class InterruptedIOException : IOException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

public open class ProtocolException : IOException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

public open class NoRouteToHostException : SocketException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

public open class UnknownServiceException : IOException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

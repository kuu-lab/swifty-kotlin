// DEBT-SEMA-003: モジュール FQN 比較ベースの可視性検証。
// 同一モジュール内で可視性を public → private に縮小する override はエラー。

open class Vehicle {
    open fun describe(): String = "Vehicle"
    protected open fun info(): String = "info"
}

class Car : Vehicle() {
    private override fun describe(): String = "Car"
}

class Truck : Vehicle() {
    private override fun info(): String = "Truck"
}

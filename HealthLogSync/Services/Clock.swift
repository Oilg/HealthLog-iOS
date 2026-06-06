import Foundation

/// Протокол для получения текущего времени. Позволяет инжектировать время в тестах.
protocol Clock {
    func now() -> Date
}

/// Системная реализация — возвращает реальное время.
struct SystemClock: Clock {
    func now() -> Date { Date() }
}

import Foundation

struct AppProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var email: String?
    var fullName: String?
    var avatarURL: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, email
        case fullName = "full_name"
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
    }
}

struct ClinicClient: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let userId: UUID
    var firstName: String
    var lastName: String
    var phone: String
    var birthDate: String?
    var gender: Gender?
    var notes: String?
    let createdAt: String?
    let updatedAt: String?

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    enum CodingKeys: String, CodingKey {
        case id, phone, gender, notes
        case userId = "user_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case birthDate = "birth_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum Gender: String, Codable, CaseIterable, Identifiable {
    case male
    case female

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male: "Мужчина"
        case .female: "Женщина"
        }
    }
}

struct Appointment: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let userId: UUID
    var clientId: UUID
    var appointmentDate: String
    var appointmentTime: String
    var service: String
    var doctorName: String?
    var status: AppointmentStatus
    var notes: String?
    var dayBeforeReminderSent: Bool
    var hourBeforeReminderSent: Bool
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, service, status, notes
        case userId = "user_id"
        case clientId = "client_id"
        case appointmentDate = "appointment_date"
        case appointmentTime = "appointment_time"
        case doctorName = "doctor_name"
        case dayBeforeReminderSent = "day_before_reminder_sent"
        case hourBeforeReminderSent = "hour_before_reminder_sent"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum AppointmentStatus: String, Codable, CaseIterable, Identifiable {
    case scheduled
    case completed
    case cancelled
    case noShow = "no_show"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scheduled: "Запланировано"
        case .completed: "Завершено"
        case .cancelled: "Отменено"
        case .noShow: "Не пришёл"
        }
    }
}

struct ClientInput: Encodable {
    let userId: UUID
    var firstName: String
    var lastName: String
    var phone: String
    var birthDate: String?
    var gender: Gender?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case phone, gender, notes
        case userId = "user_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case birthDate = "birth_date"
    }
}

struct AppointmentInput: Encodable {
    let userId: UUID
    var clientId: UUID
    var appointmentDate: String
    var appointmentTime: String
    var service: String
    var doctorName: String?
    var status: AppointmentStatus
    var notes: String?
    var dayBeforeReminderSent: Bool
    var hourBeforeReminderSent: Bool

    enum CodingKeys: String, CodingKey {
        case service, status, notes
        case userId = "user_id"
        case clientId = "client_id"
        case appointmentDate = "appointment_date"
        case appointmentTime = "appointment_time"
        case doctorName = "doctor_name"
        case dayBeforeReminderSent = "day_before_reminder_sent"
        case hourBeforeReminderSent = "hour_before_reminder_sent"
    }
}

struct AppointmentDisplay: Identifiable, Equatable {
    let appointment: Appointment
    let client: ClinicClient?

    var id: UUID { appointment.id }
}

enum AppError: LocalizedError {
    case missingConfiguration
    case unauthenticated
    case invalidPhone
    case validation(String)
    case network
    case unknown

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "Не настроено подключение к Supabase."
        case .unauthenticated:
            "Необходимо войти в аккаунт."
        case .invalidPhone:
            "Введите телефон в формате +998 XX XXX XX XX."
        case .validation(let message):
            message
        case .network:
            "Не удалось сохранить данные. Проверьте подключение к интернету."
        case .unknown:
            "Что-то пошло не так. Попробуйте ещё раз."
        }
    }
}

enum DateText {
    static let dbDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let dbTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static let ruDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    static func dateString(from date: Date) -> String {
        dbDate.string(from: date)
    }

    static func timeString(from date: Date) -> String {
        dbTime.string(from: date)
    }

    static func shortTime(_ dbValue: String) -> String {
        String(dbValue.prefix(5))
    }

    static func displayDate(_ dbValue: String?) -> String {
        guard let dbValue, let date = dbDate.date(from: dbValue) else { return "Не указано" }
        return ruDate.string(from: date)
    }
}

enum PhoneFormatter {
    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidUzbekPhone(_ value: String) -> Bool {
        let pattern = #"^\+998\s?\d{2}\s?\d{3}\s?\d{2}\s?\d{2}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}

import Foundation
import Supabase

struct AppConfig {
    let supabaseURL: URL
    let supabaseAnonKey: String

    static func load() throws -> AppConfig {
        guard
            let urlValue = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
            let anonKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
            !urlValue.isEmpty,
            !anonKey.isEmpty,
            !urlValue.contains("$("),
            !anonKey.contains("$("),
            let url = URL(string: urlValue)
        else {
            throw AppError.missingConfiguration
        }

        return AppConfig(supabaseURL: url, supabaseAnonKey: anonKey)
    }
}

final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        do {
            let config = try AppConfig.load()
            client = SupabaseClient(supabaseURL: config.supabaseURL, supabaseKey: config.supabaseAnonKey)
        } catch {
            let fallbackURL = URL(string: "https://example.supabase.co") ?? URL(fileURLWithPath: "/")
            client = SupabaseClient(supabaseURL: fallbackURL, supabaseKey: "missing")
        }
    }
}

protocol AuthServicing {
    func currentUserId() async throws -> UUID?
    func signInWithGoogle() async throws
    func handleAuthCallback(_ url: URL) async throws
    func ensureProfile() async throws -> AppProfile
    func signOut() async throws
}

final class AuthService: AuthServicing {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseService.shared.client) {
        self.supabase = supabase
    }

    func currentUserId() async throws -> UUID? {
        do {
            return try await supabase.auth.user().id
        } catch {
            return nil
        }
    }

    func signInWithGoogle() async throws {
        guard let redirectURL = URL(string: "\(Bundle.main.bundleIdentifier ?? "uz.clinika.mvp")://login-callback") else {
            throw AppError.missingConfiguration
        }

        try await supabase.auth.signInWithOAuth(provider: .google, redirectTo: redirectURL)
    }

    func handleAuthCallback(_ url: URL) async throws {
        try await supabase.auth.session(from: url)
    }

    func ensureProfile() async throws -> AppProfile {
        let user = try await supabase.auth.user()
        let displayName = user.email?.split(separator: "@").first.map(String.init)

        let input = ProfileInput(
            id: user.id,
            email: user.email,
            fullName: displayName,
            avatarURL: nil
        )

        return try await supabase
            .from("profiles")
            .upsert(input)
            .select()
            .single()
            .execute()
            .value
    }

    func signOut() async throws {
        try await supabase.auth.signOut()
    }
}

private struct ProfileInput: Encodable {
    let id: UUID
    let email: String?
    let fullName: String?
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id, email
        case fullName = "full_name"
        case avatarURL = "avatar_url"
    }
}

protocol ClientServicing {
    func fetchClients(userId: UUID) async throws -> [ClinicClient]
    func createClient(_ input: ClientInput) async throws -> ClinicClient
    func updateClient(id: UUID, input: ClientInput) async throws -> ClinicClient
    func deleteClient(id: UUID) async throws
}

final class ClientService: ClientServicing {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseService.shared.client) {
        self.supabase = supabase
    }

    func fetchClients(userId: UUID) async throws -> [ClinicClient] {
        try await supabase
            .from("clients")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func createClient(_ input: ClientInput) async throws -> ClinicClient {
        try await supabase
            .from("clients")
            .insert(input)
            .select()
            .single()
            .execute()
            .value
    }

    func updateClient(id: UUID, input: ClientInput) async throws -> ClinicClient {
        try await supabase
            .from("clients")
            .update(input)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteClient(id: UUID) async throws {
        _ = try await supabase
            .from("clients")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}

protocol AppointmentServicing {
    func fetchAppointments(userId: UUID) async throws -> [Appointment]
    func fetchAppointments(userId: UUID, date: Date) async throws -> [Appointment]
    func fetchAppointments(userId: UUID, clientId: UUID) async throws -> [Appointment]
    func createAppointment(_ input: AppointmentInput) async throws -> Appointment
    func updateAppointment(id: UUID, input: AppointmentInput) async throws -> Appointment
    func deleteAppointment(id: UUID) async throws
}

final class AppointmentService: AppointmentServicing {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseService.shared.client) {
        self.supabase = supabase
    }

    func fetchAppointments(userId: UUID) async throws -> [Appointment] {
        try await supabase
            .from("appointments")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("appointment_date", ascending: true)
            .order("appointment_time", ascending: true)
            .execute()
            .value
    }

    func fetchAppointments(userId: UUID, date: Date) async throws -> [Appointment] {
        try await supabase
            .from("appointments")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("appointment_date", value: DateText.dateString(from: date))
            .order("appointment_time", ascending: true)
            .execute()
            .value
    }

    func fetchAppointments(userId: UUID, clientId: UUID) async throws -> [Appointment] {
        try await supabase
            .from("appointments")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("client_id", value: clientId.uuidString)
            .order("appointment_date", ascending: false)
            .order("appointment_time", ascending: false)
            .execute()
            .value
    }

    func createAppointment(_ input: AppointmentInput) async throws -> Appointment {
        try await supabase
            .from("appointments")
            .insert(input)
            .select()
            .single()
            .execute()
            .value
    }

    func updateAppointment(id: UUID, input: AppointmentInput) async throws -> Appointment {
        try await supabase
            .from("appointments")
            .update(input)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteAppointment(id: UUID) async throws {
        _ = try await supabase
            .from("appointments")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}

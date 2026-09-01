import Combine
import Foundation

enum SessionState: Equatable {
    case splash
    case signedOut
    case signedIn(AppProfile)
}

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var state: SessionState = .splash
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let authService: AuthServicing

    init(authService: AuthServicing = AuthService()) {
        self.authService = authService
    }

    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if try await authService.currentUserId() != nil {
                let profile = try await authService.ensureProfile()
                state = .signedIn(profile)
            } else {
                state = .signedOut
            }
        } catch {
            state = .signedOut
        }
    }

    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try AppConfig.load()
            try await authService.signInWithGoogle()
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func handleOpenURL(_ url: URL) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authService.handleAuthCallback(url)
            let profile = try await authService.ensureProfile()
            state = .signedIn(profile)
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func signOut() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await authService.signOut()
            state = .signedOut
        } catch {
            errorMessage = userMessage(for: error)
        }
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var todayAppointments: [AppointmentDisplay] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    var completedCount: Int { count(.completed) }
    var scheduledCount: Int { count(.scheduled) }
    var cancelledCount: Int { count(.cancelled) }
    var totalCount: Int { todayAppointments.count }

    private let userId: UUID
    private let clientService: ClientServicing
    private let appointmentService: AppointmentServicing

    init(
        userId: UUID,
        clientService: ClientServicing = ClientService(),
        appointmentService: AppointmentServicing = AppointmentService()
    ) {
        self.userId = userId
        self.clientService = clientService
        self.appointmentService = appointmentService
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let clients = clientService.fetchClients(userId: userId)
            async let appointments = appointmentService.fetchAppointments(userId: userId, date: Date())
            let fetchedClients = try await clients
            let fetchedAppointments = try await appointments
            let clientMap = Dictionary(uniqueKeysWithValues: fetchedClients.map { ($0.id, $0) })
            todayAppointments = fetchedAppointments.map { AppointmentDisplay(appointment: $0, client: clientMap[$0.clientId]) }
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    private func count(_ status: AppointmentStatus) -> Int {
        todayAppointments.filter { $0.appointment.status == status }.count
    }
}

@MainActor
final class ClientsViewModel: ObservableObject {
    @Published var clients: [ClinicClient] = []
    @Published var lastVisitByClientId: [UUID: String] = [:]
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let userId: UUID
    private let clientService: ClientServicing
    private let appointmentService: AppointmentServicing

    init(
        userId: UUID,
        clientService: ClientServicing = ClientService(),
        appointmentService: AppointmentServicing = AppointmentService()
    ) {
        self.userId = userId
        self.clientService = clientService
        self.appointmentService = appointmentService
    }

    var filteredClients: [ClinicClient] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return clients }

        return clients.filter {
            $0.firstName.lowercased().contains(query)
                || $0.lastName.lowercased().contains(query)
                || $0.phone.lowercased().contains(query)
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let fetchedClients = clientService.fetchClients(userId: userId)
            async let fetchedAppointments = appointmentService.fetchAppointments(userId: userId)
            clients = try await fetchedClients
            lastVisitByClientId = Self.makeLastVisitLookup(from: try await fetchedAppointments)
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    private static func makeLastVisitLookup(from appointments: [Appointment]) -> [UUID: String] {
        let today = DateText.dateString(from: Date())
        var lookup: [UUID: String] = [:]

        for appointment in appointments where appointment.appointmentDate <= today {
            if let current = lookup[appointment.clientId] {
                if appointment.appointmentDate > current {
                    lookup[appointment.clientId] = appointment.appointmentDate
                }
            } else {
                lookup[appointment.clientId] = appointment.appointmentDate
            }
        }

        return lookup
    }
}

@MainActor
final class ClientFormViewModel: ObservableObject {
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var phone = ""
    @Published var birthDate = Date()
    @Published var includesBirthDate = false
    @Published var gender: Gender?
    @Published var notes = ""
    @Published var isSaving = false
    @Published var errorMessage: String?

    private let userId: UUID
    private let clientService: ClientServicing
    private let existingClient: ClinicClient?

    init(userId: UUID, client: ClinicClient? = nil, clientService: ClientServicing = ClientService()) {
        self.userId = userId
        self.existingClient = client
        self.clientService = clientService

        if let client {
            firstName = client.firstName
            lastName = client.lastName
            phone = client.phone
            notes = client.notes ?? ""
            gender = client.gender
            if let birthDateValue = client.birthDate, let parsedDate = DateText.dbDate.date(from: birthDateValue) {
                birthDate = parsedDate
                includesBirthDate = true
            }
        }
    }

    func save() async -> ClinicClient? {
        guard validate() else { return nil }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let input = ClientInput(
            userId: userId,
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: PhoneFormatter.normalize(phone),
            birthDate: includesBirthDate ? DateText.dateString(from: birthDate) : nil,
            gender: gender,
            notes: notes.trimmedOrNil
        )

        do {
            if let existingClient {
                return try await clientService.updateClient(id: existingClient.id, input: input)
            } else {
                return try await clientService.createClient(input)
            }
        } catch {
            errorMessage = userMessage(for: error)
            return nil
        }
    }

    private func validate() -> Bool {
        if firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Введите имя клиента."
            return false
        }

        if lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Введите фамилию клиента."
            return false
        }

        if !PhoneFormatter.isValidUzbekPhone(PhoneFormatter.normalize(phone)) {
            errorMessage = AppError.invalidPhone.localizedDescription
            return false
        }

        return true
    }
}

@MainActor
final class ClientDetailViewModel: ObservableObject {
    @Published var appointments: [Appointment] = []
    @Published var isLoading = false
    @Published var isDeleting = false
    @Published var errorMessage: String?

    private let userId: UUID
    private let clientService: ClientServicing
    private let appointmentService: AppointmentServicing

    init(
        userId: UUID,
        clientService: ClientServicing = ClientService(),
        appointmentService: AppointmentServicing = AppointmentService()
    ) {
        self.userId = userId
        self.clientService = clientService
        self.appointmentService = appointmentService
    }

    func loadHistory(for client: ClinicClient) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            appointments = try await appointmentService.fetchAppointments(userId: userId, clientId: client.id)
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func delete(_ client: ClinicClient) async -> Bool {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            try await clientService.deleteClient(id: client.id)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }
}

@MainActor
final class AppointmentsViewModel: ObservableObject {
    @Published var selectedDate = Date()
    @Published var selectedStatus: AppointmentStatus?
    @Published var appointments: [AppointmentDisplay] = []
    @Published var clients: [ClinicClient] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let userId: UUID
    private let clientService: ClientServicing
    private let appointmentService: AppointmentServicing

    init(
        userId: UUID,
        clientService: ClientServicing = ClientService(),
        appointmentService: AppointmentServicing = AppointmentService()
    ) {
        self.userId = userId
        self.clientService = clientService
        self.appointmentService = appointmentService
    }

    var filteredAppointments: [AppointmentDisplay] {
        guard let selectedStatus else { return appointments }
        return appointments.filter { $0.appointment.status == selectedStatus }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let fetchedClients = clientService.fetchClients(userId: userId)
            async let fetchedAppointments = appointmentService.fetchAppointments(userId: userId, date: selectedDate)
            clients = try await fetchedClients
            let clientMap = Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0) })
            let dayAppointments = try await fetchedAppointments
            appointments = dayAppointments.map { AppointmentDisplay(appointment: $0, client: clientMap[$0.clientId]) }
        } catch {
            errorMessage = userMessage(for: error)
        }
    }
}

@MainActor
final class AppointmentFormViewModel: ObservableObject {
    @Published var selectedClient: ClinicClient?
    @Published var date = Date()
    @Published var time = Date()
    @Published var service = "Консультация"
    @Published var customService = ""
    @Published var doctorName = ""
    @Published var notes = ""
    @Published var status: AppointmentStatus = .scheduled
    @Published var isSaving = false
    @Published var isDeleting = false
    @Published var errorMessage: String?

    let services = [
        "Консультация",
        "Лечение кариеса",
        "Чистка зубов",
        "Удаление зуба",
        "Имплантация",
        "Отбеливание",
        "Другое"
    ]

    private let userId: UUID
    private let appointmentService: AppointmentServicing
    private let existingAppointment: Appointment?

    init(
        userId: UUID,
        clients: [ClinicClient],
        appointment: Appointment? = nil,
        appointmentService: AppointmentServicing = AppointmentService()
    ) {
        self.userId = userId
        self.existingAppointment = appointment
        self.appointmentService = appointmentService

        if let appointment {
            selectedClient = clients.first { $0.id == appointment.clientId }
            date = DateText.dbDate.date(from: appointment.appointmentDate) ?? Date()
            time = DateText.dbTime.date(from: appointment.appointmentTime) ?? Date()
            if services.contains(appointment.service) {
                service = appointment.service
            } else {
                service = "Другое"
                customService = appointment.service
            }
            doctorName = appointment.doctorName ?? ""
            notes = appointment.notes ?? ""
            status = appointment.status
        }
    }

    func save() async -> Appointment? {
        guard let selectedClient else {
            errorMessage = "Выберите клиента для записи."
            return nil
        }

        let finalService = service == "Другое" ? customService.trimmedOrNil : service
        guard let finalService, !finalService.isEmpty else {
            errorMessage = "Введите услугу."
            return nil
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let input = AppointmentInput(
            userId: userId,
            clientId: selectedClient.id,
            appointmentDate: DateText.dateString(from: date),
            appointmentTime: DateText.timeString(from: time),
            service: finalService,
            doctorName: doctorName.trimmedOrNil,
            status: status,
            notes: notes.trimmedOrNil,
            dayBeforeReminderSent: existingAppointment?.dayBeforeReminderSent ?? false,
            hourBeforeReminderSent: existingAppointment?.hourBeforeReminderSent ?? false
        )

        do {
            if let existingAppointment {
                return try await appointmentService.updateAppointment(id: existingAppointment.id, input: input)
            } else {
                return try await appointmentService.createAppointment(input)
            }
        } catch {
            errorMessage = userMessage(for: error)
            return nil
        }
    }

    func delete() async -> Bool {
        guard let existingAppointment else { return false }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            try await appointmentService.deleteAppointment(id: existingAppointment.id)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }
}

func userMessage(for error: Error) -> String {
    if let appError = error as? AppError {
        return appError.localizedDescription
    }

    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
        return AppError.network.localizedDescription
    }

    return AppError.unknown.localizedDescription
}

private extension String {
    var trimmedOrNil: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

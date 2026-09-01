import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var session: SessionViewModel

    var body: some View {
        Group {
            switch session.state {
            case .splash:
                SplashView()
            case .signedOut:
                LoginView()
            case .signedIn(let profile):
                MainTabView(profile: profile)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.state)
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cross.case.fill")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
            Text("Клиника")
                .font(.largeTitle.bold())
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

struct LoginView: View {
    @EnvironmentObject private var session: SessionViewModel

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("Клиника")
                    .font(.largeTitle.bold())
                Text("Управление стоматологической клиникой")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let error = session.errorMessage {
                ErrorBanner(message: error)
            }

            Button {
                Task { await session.signInWithGoogle() }
            } label: {
                Label("Продолжить с Google", systemImage: "globe")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(session.isLoading)

            Spacer()
        }
        .padding(24)
        .background(Color(.systemGroupedBackground))
    }
}

struct MainTabView: View {
    let profile: AppProfile

    var body: some View {
        TabView {
            DashboardView(profile: profile)
                .tabItem { Label("Главная", systemImage: "house") }
            ClientsView(userId: profile.id)
                .tabItem { Label("Клиенты", systemImage: "person.2") }
            AppointmentsView(userId: profile.id)
                .tabItem { Label("Записи", systemImage: "calendar") }
            ProfileView(profile: profile)
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
        }
    }
}

struct DashboardView: View {
    let profile: AppProfile
    @StateObject private var viewModel: DashboardViewModel

    init(profile: AppProfile) {
        self.profile = profile
        _viewModel = StateObject(wrappedValue: DashboardViewModel(userId: profile.id))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Добро пожаловать, \(profile.fullName ?? "доктор")")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    StatsCard(
                        total: viewModel.totalCount,
                        completed: viewModel.completedCount,
                        scheduled: viewModel.scheduledCount,
                        cancelled: viewModel.cancelledCount
                    )

                    SectionHeader(title: "Сегодняшние записи")

                    if viewModel.isLoading {
                        ProgressView("Загрузка записей...")
                            .frame(maxWidth: .infinity)
                    } else if viewModel.todayAppointments.isEmpty {
                        EmptyStateView(title: "На сегодня записей нет.", subtitle: "Новые записи появятся здесь.")
                    } else {
                        ForEach(viewModel.todayAppointments) { display in
                            NavigationLink {
                                AppointmentDetailView(userId: profile.id, display: display, clients: display.client.map { [$0] } ?? [])
                            } label: {
                                AppointmentCard(display: display)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Главная")
            .background(Color(.systemGroupedBackground))
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .alert("Ошибка", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}

struct ClientsView: View {
    let userId: UUID
    @StateObject private var viewModel: ClientsViewModel
    @State private var isShowingForm = false

    init(userId: UUID) {
        self.userId = userId
        _viewModel = StateObject(wrappedValue: ClientsViewModel(userId: userId))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Загрузка клиентов...")
                } else if viewModel.filteredClients.isEmpty {
                    EmptyStateView(title: "Клиентов пока нет", subtitle: "Добавьте первого клиента, чтобы начать работу.", actionTitle: "Добавить клиента") {
                        isShowingForm = true
                    }
                } else {
                    List(viewModel.filteredClients) { client in
                        NavigationLink {
                            ClientDetailView(userId: client.userId, client: client)
                        } label: {
                            ClientRow(client: client, lastVisit: viewModel.lastVisitByClientId[client.id])
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Клиенты")
            .searchable(text: $viewModel.searchText, prompt: "Имя, фамилия или телефон")
            .toolbar {
                Button {
                    isShowingForm = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(isPresented: $isShowingForm, onDismiss: {
                Task { await viewModel.load() }
            }) {
                ClientFormView(userId: userId)
            }
            .alert("Ошибка", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}

struct ClientFormView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ClientFormViewModel

    init(userId: UUID, client: ClinicClient? = nil) {
        _viewModel = StateObject(wrappedValue: ClientFormViewModel(userId: userId, client: client))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Основная информация") {
                    TextField("Имя *", text: $viewModel.firstName)
                    TextField("Фамилия *", text: $viewModel.lastName)
                    TextField("+998 XX XXX XX XX", text: $viewModel.phone)
                        .keyboardType(.phonePad)
                }

                Section {
                    Toggle("Дата рождения", isOn: $viewModel.includesBirthDate)
                    if viewModel.includesBirthDate {
                        DatePicker("Дата", selection: $viewModel.birthDate, displayedComponents: .date)
                    }
                    Picker("Пол", selection: $viewModel.gender) {
                        Text("Не указан").tag(Gender?.none)
                        ForEach(Gender.allCases) { gender in
                            Text(gender.title).tag(Gender?.some(gender))
                        }
                    }
                    TextField("Примечания", text: $viewModel.notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let error = viewModel.errorMessage {
                    Section {
                        ErrorBanner(message: error)
                    }
                }
            }
            .navigationTitle("Клиент")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        Task {
                            if await viewModel.save() != nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            .overlay {
                if viewModel.isSaving {
                    ProgressView("Сохранение...")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }
}

struct ClientDetailView: View {
    let userId: UUID
    let client: ClinicClient

    @StateObject private var viewModel: ClientDetailViewModel
    @State private var isShowingEdit = false
    @State private var isConfirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    init(userId: UUID, client: ClinicClient) {
        self.userId = userId
        self.client = client
        _viewModel = StateObject(wrappedValue: ClientDetailViewModel(userId: userId))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(client.fullName)
                            .font(.title2.bold())
                        Label(client.phone, systemImage: "phone")
                        Label(DateText.displayDate(client.birthDate), systemImage: "calendar")
                        Label(client.gender?.title ?? "Пол не указан", systemImage: "person")
                        if let notes = client.notes, !notes.isEmpty {
                            Text(notes)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack {
                    Button {
                        if let url = URL(string: "tel://\(client.phone.replacingOccurrences(of: " ", with: ""))") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Позвонить", systemImage: "phone.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Редактировать") {
                        isShowingEdit = true
                    }
                    .buttonStyle(.bordered)
                }

                SectionHeader(title: "История записей")
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.appointments.isEmpty {
                    EmptyStateView(title: "История пуста", subtitle: "Записи клиента появятся здесь.")
                } else {
                    ForEach(viewModel.appointments) { appointment in
                        HistoryRow(appointment: appointment)
                    }
                }

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Удалить", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isDeleting)
            }
            .padding()
        }
        .navigationTitle("Клиент")
        .background(Color(.systemGroupedBackground))
        .task { await viewModel.loadHistory(for: client) }
        .sheet(isPresented: $isShowingEdit) {
            ClientFormView(userId: userId, client: client)
        }
        .confirmationDialog("Удалить клиента?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                Task {
                    if await viewModel.delete(client) {
                        dismiss()
                    }
                }
            }
            Button("Отмена", role: .cancel) {}
        }
    }
}

struct AppointmentsView: View {
    let userId: UUID
    @StateObject private var viewModel: AppointmentsViewModel
    @State private var isShowingForm = false

    init(userId: UUID) {
        self.userId = userId
        _viewModel = StateObject(wrappedValue: AppointmentsViewModel(userId: userId))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                DatePicker("Дата", selection: $viewModel.selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .padding(.horizontal)

                Picker("Статус", selection: $viewModel.selectedStatus) {
                    Text("Все").tag(AppointmentStatus?.none)
                    ForEach(AppointmentStatus.allCases) { status in
                        Text(status.title).tag(AppointmentStatus?.some(status))
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)

                Group {
                    if viewModel.isLoading {
                        ProgressView("Загрузка записей...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.filteredAppointments.isEmpty {
                        EmptyStateView(title: "На этот день записей нет.", subtitle: "Добавьте новую запись.", actionTitle: "Добавить новую запись") {
                            isShowingForm = true
                        }
                    } else {
                        List(viewModel.filteredAppointments) { display in
                            NavigationLink {
                                AppointmentDetailView(userId: userId, display: display, clients: viewModel.clients)
                            } label: {
                                AppointmentCard(display: display, showsEndTime: true)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Записи")
            .toolbar {
                Button {
                    isShowingForm = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .onChange(of: viewModel.selectedDate) { _, _ in
                Task { await viewModel.load() }
            }
            .sheet(isPresented: $isShowingForm, onDismiss: {
                Task { await viewModel.load() }
            }) {
                AppointmentFormView(userId: userId, clients: viewModel.clients)
            }
        }
    }
}

struct AppointmentDetailView: View {
    let userId: UUID
    let display: AppointmentDisplay
    let clients: [ClinicClient]

    @State private var isShowingEdit = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(display.client?.fullName ?? "Клиент не найден")
                            .font(.title2.bold())
                        Label("\(DateText.displayDate(display.appointment.appointmentDate)) в \(DateText.shortTime(display.appointment.appointmentTime))", systemImage: "calendar")
                        Label(display.appointment.service, systemImage: "stethoscope")
                        Label(display.client?.phone ?? "Телефон не указан", systemImage: "phone")
                        Label(display.appointment.status.title, systemImage: "checkmark.circle")
                        if let doctor = display.appointment.doctorName {
                            Label(doctor, systemImage: "person.text.rectangle")
                        }
                        if let notes = display.appointment.notes {
                            Text(notes)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Запись")
        .background(Color(.systemGroupedBackground))
        .toolbar {
            Button("Редактировать") {
                isShowingEdit = true
            }
        }
        .sheet(isPresented: $isShowingEdit) {
            AppointmentFormView(userId: userId, clients: clients, appointment: display.appointment)
        }
    }
}

struct AppointmentFormView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AppointmentFormViewModel
    @State private var isConfirmingDelete = false
    private let clients: [ClinicClient]
    private let appointment: Appointment?

    init(userId: UUID, clients: [ClinicClient], appointment: Appointment? = nil) {
        self.clients = clients
        self.appointment = appointment
        _viewModel = StateObject(wrappedValue: AppointmentFormViewModel(userId: userId, clients: clients, appointment: appointment))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Клиент") {
                    if clients.isEmpty {
                        Text("Сначала добавьте клиента.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Клиент", selection: $viewModel.selectedClient) {
                            Text("Выберите клиента").tag(ClinicClient?.none)
                            ForEach(clients) { client in
                                Text(client.fullName).tag(ClinicClient?.some(client))
                            }
                        }
                    }
                }

                Section("Дата и время") {
                    DatePicker("Дата", selection: $viewModel.date, displayedComponents: .date)
                    DatePicker("Время", selection: $viewModel.time, displayedComponents: .hourAndMinute)
                }

                Section("Услуга") {
                    Picker("Услуга", selection: $viewModel.service) {
                        ForEach(viewModel.services, id: \.self) { service in
                            Text(service).tag(service)
                        }
                    }
                    if viewModel.service == "Другое" {
                        TextField("Введите услугу", text: $viewModel.customService)
                    }
                }

                Section {
                    TextField("Врач", text: $viewModel.doctorName)
                    TextField("Примечания", text: $viewModel.notes, axis: .vertical)
                        .lineLimit(3...6)
                    Picker("Статус", selection: $viewModel.status) {
                        ForEach(AppointmentStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                }

                if appointment != nil {
                    Section {
                        Button("Удалить запись", role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .disabled(viewModel.isDeleting)
                    }
                }

                if let error = viewModel.errorMessage {
                    Section {
                        ErrorBanner(message: error)
                    }
                }
            }
            .navigationTitle(appointment == nil ? "Новая запись" : "Редактировать")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(appointment == nil ? "Создать запись" : "Сохранить") {
                        Task {
                            if await viewModel.save() != nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isSaving || clients.isEmpty)
                }
            }
            .confirmationDialog("Удалить запись?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    Task {
                        if await viewModel.delete() {
                            dismiss()
                        }
                    }
                }
                Button("Отмена", role: .cancel) {}
            }
            .overlay {
                if viewModel.isSaving || viewModel.isDeleting {
                    ProgressView(viewModel.isDeleting ? "Удаление..." : "Сохранение...")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var session: SessionViewModel
    let profile: AppProfile

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 76))
                    .foregroundStyle(.tint)
                Text(profile.fullName ?? "Пользователь")
                    .font(.title2.bold())
                Text(profile.email ?? "Email не указан")
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    Task { await session.signOut() }
                } label: {
                    Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.top, 24)

                Spacer()
            }
            .padding()
            .navigationTitle("Профиль")
            .background(Color(.systemGroupedBackground))
        }
    }
}

struct StatsCard: View {
    let total: Int
    let completed: Int
    let scheduled: Int
    let cancelled: Int

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Сегодня")
                    .foregroundStyle(.secondary)
                Text("\(total) записей")
                    .font(.largeTitle.bold())
                HStack {
                    StatPill(title: "Завершено", value: completed)
                    StatPill(title: "Ожидается", value: scheduled)
                    StatPill(title: "Отменено", value: cancelled)
                }
            }
        }
    }
}

struct StatPill: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppointmentCard: View {
    let display: AppointmentDisplay
    var showsEndTime = false

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 16) {
                Text(timeText)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.tint)
                    .frame(width: showsEndTime ? 96 : 54, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text(display.client?.fullName ?? "Клиент не найден")
                        .font(.headline)
                    Text(display.appointment.service)
                    Text(display.client?.phone ?? "Телефон не указан")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(display.appointment.status.title)
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    private var timeText: String {
        let start = DateText.shortTime(display.appointment.appointmentTime)
        guard showsEndTime, let date = DateText.dbTime.date(from: display.appointment.appointmentTime) else {
            return start
        }
        let end = Calendar.current.date(byAdding: .hour, value: 1, to: date).map(DateText.dbTime.string(from:)).map(DateText.shortTime) ?? ""
        return "\(start) — \(end)"
    }
}

struct ClientRow: View {
    let client: ClinicClient
    let lastVisit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(client.fullName)
                .font(.headline)
            Text(client.phone)
                .foregroundStyle(.secondary)
            Text("Последний визит: \(DateText.displayDate(lastVisit))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

struct HistoryRow: View {
    let appointment: Appointment

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(DateText.displayDate(appointment.appointmentDate))
                    .font(.headline)
                Text(appointment.service)
                HStack {
                    Text(DateText.shortTime(appointment.appointmentTime))
                    Spacer()
                    Text(appointment.status.title)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct Card<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyStateView: View {
    let title: String
    let subtitle: String
    var actionTitle = "Добавить"
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let action {
                Button(actionTitle) { action() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

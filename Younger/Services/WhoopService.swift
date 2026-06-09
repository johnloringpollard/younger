import AuthenticationServices
import Foundation
import Security

actor WhoopService {
    static let shared = WhoopService()

    private let baseURL = URL(string: "https://api.prod.whoop.com/developer/v2/")!
    private let legacyTokenKey = "com.younger.whoop.access-token"
    private let sessionTokenKey = "com.younger.whoop.session-token"
    private let backendBaseURL = URL(string: "https://us-central1-younger-jlp.cloudfunctions.net/")!

    var hasToken: Bool {
        KeychainStore.read(key: sessionTokenKey) != nil ||
            KeychainStore.read(key: legacyTokenKey) != nil
    }

    func exchangeTicket(_ ticket: String) async throws {
        var request = URLRequest(url: backendURL("whoopExchangeTicket"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["ticket": ticket])

        let response: TicketResponse = try await backendRequest(request)
        try KeychainStore.save(response.sessionToken, key: sessionTokenKey)
        KeychainStore.delete(key: legacyTokenKey)
    }

    func disconnect() async {
        if let sessionToken = KeychainStore.read(key: sessionTokenKey) {
            var request = URLRequest(url: backendURL("whoopDisconnect"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
        KeychainStore.delete(key: sessionTokenKey)
        KeychainStore.delete(key: legacyTokenKey)
    }

    func fetchSnapshot() async throws -> WhoopSnapshot {
        if let sessionToken = KeychainStore.read(key: sessionTokenKey) {
            var request = URLRequest(url: backendURL("whoopSnapshot"))
            request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
            let snapshot: BackendSnapshot = try await backendRequest(request)
            return snapshot.whoopSnapshot
        }

        guard let token = KeychainStore.read(key: legacyTokenKey) else {
            throw WhoopError.missingToken
        }

        async let recoveries: RecoveryCollection = request("recovery?limit=1", token: token)
        async let cycles: CycleCollection = request("cycle?limit=1", token: token)
        async let sleeps: SleepCollection = request("activity/sleep?limit=1", token: token)
        async let workouts: WorkoutCollection = request("activity/workout?limit=10", token: token)

        let recovery = try await recoveries.records.first?.score
        let cycle = try await cycles.records.first?.score
        let sleep = try await sleeps.records.first?.score
        let recentWorkouts = try await workouts.records
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let zoneMillis = recentWorkouts
            .filter { ($0.startDate ?? .distantPast) >= startOfDay }
            .compactMap(\.score?.zoneDuration)
            .reduce(0) { partial, zones in
                partial + zones.zoneTwo + zones.zoneThree + zones.zoneFour + zones.zoneFive
            }

        return WhoopSnapshot(
            recoveryScore: recovery?.recoveryScore,
            strain: cycle?.strain,
            sleepHours: sleep?.stageSummary.sleepHours,
            sleepPerformance: sleep?.sleepPerformance,
            hrv: recovery?.hrv,
            restingHeartRate: recovery?.restingHeartRate,
            respiratoryRate: sleep?.respiratoryRate,
            oxygenSaturation: recovery?.oxygenSaturation,
            skinTemperature: recovery?.skinTemperature,
            zoneMinutes: Double(zoneMillis) / 60_000
        )
    }

    private func request<T: Decodable>(_ path: String, token: String) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw WhoopError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WhoopError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw WhoopError.unauthorized }
            throw WhoopError.server(http.statusCode)
        }
        return try JSONDecoder.whoop.decode(T.self, from: data)
    }

    private func backendURL(_ functionName: String) -> URL {
        backendBaseURL.appendingPathComponent(functionName)
    }

    private func backendRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WhoopError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw WhoopError.unauthorized }
            throw WhoopError.server(http.statusCode)
        }
        return try JSONDecoder.whoop.decode(T.self, from: data)
    }
}

@MainActor
final class WhoopOAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WhoopOAuthCoordinator()

    private let authorizationURL = URL(
        string: "https://us-central1-younger-jlp.cloudfunctions.net/whoopAuthStart"
    )!
    private var session: ASWebAuthenticationSession?

    func authenticate() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: "younger"
            ) { [weak self] callbackURL, error in
                self?.session = nil
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
                    continuation.resume(throwing: WhoopError.invalidCallback)
                    return
                }
                let parameters = Dictionary(
                    uniqueKeysWithValues: components.queryItems?.compactMap { item in
                        item.value.map { (item.name, $0) }
                    } ?? []
                )
                if let error = parameters["error"] {
                    continuation.resume(throwing: WhoopError.oauth(error))
                    return
                }
                guard let ticket = parameters["ticket"], !ticket.isEmpty else {
                    continuation.resume(throwing: WhoopError.invalidCallback)
                    return
                }
                continuation.resume(returning: ticket)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                self.session = nil
                continuation.resume(throwing: WhoopError.couldNotStartOAuth)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

private struct TicketResponse: Decodable {
    let sessionToken: String

    enum CodingKeys: String, CodingKey {
        case sessionToken = "session_token"
    }
}

private struct BackendSnapshot: Decodable {
    let recoveryScore: Double?
    let strain: Double?
    let sleepHours: Double?
    let sleepPerformance: Double?
    let hrv: Double?
    let restingHeartRate: Double?
    let respiratoryRate: Double?
    let oxygenSaturation: Double?
    let skinTemperature: Double?
    let zoneMinutes: Double?

    var whoopSnapshot: WhoopSnapshot {
        WhoopSnapshot(
            recoveryScore: recoveryScore,
            strain: strain,
            sleepHours: sleepHours,
            sleepPerformance: sleepPerformance,
            hrv: hrv,
            restingHeartRate: restingHeartRate,
            respiratoryRate: respiratoryRate,
            oxygenSaturation: oxygenSaturation,
            skinTemperature: skinTemperature,
            zoneMinutes: zoneMinutes
        )
    }

    enum CodingKeys: String, CodingKey {
        case recoveryScore = "recovery_score"
        case strain
        case sleepHours = "sleep_hours"
        case sleepPerformance = "sleep_performance"
        case hrv
        case restingHeartRate = "resting_heart_rate"
        case respiratoryRate = "respiratory_rate"
        case oxygenSaturation = "oxygen_saturation"
        case skinTemperature = "skin_temperature"
        case zoneMinutes = "zone_minutes"
    }
}

private struct RecoveryCollection: Decodable {
    let records: [RecoveryRecord]
}

private struct RecoveryRecord: Decodable {
    let score: RecoveryScore?
}

private struct RecoveryScore: Decodable {
    let recoveryScore: Double
    let restingHeartRate: Double
    let hrv: Double
    let oxygenSaturation: Double?
    let skinTemperature: Double?

    enum CodingKeys: String, CodingKey {
        case recoveryScore = "recovery_score"
        case restingHeartRate = "resting_heart_rate"
        case hrv = "hrv_rmssd_milli"
        case oxygenSaturation = "spo2_percentage"
        case skinTemperature = "skin_temp_celsius"
    }
}

private struct CycleCollection: Decodable {
    let records: [CycleRecord]
}

private struct CycleRecord: Decodable {
    let score: CycleScore?
}

private struct CycleScore: Decodable {
    let strain: Double
}

private struct SleepCollection: Decodable {
    let records: [SleepRecord]
}

private struct SleepRecord: Decodable {
    let score: SleepScore?
}

private struct SleepScore: Decodable {
    let stageSummary: StageSummary
    let sleepPerformance: Double
    let respiratoryRate: Double

    enum CodingKeys: String, CodingKey {
        case stageSummary = "stage_summary"
        case sleepPerformance = "sleep_performance_percentage"
        case respiratoryRate = "respiratory_rate"
    }
}

private struct StageSummary: Decodable {
    let light: Double
    let deep: Double
    let rem: Double

    var sleepHours: Double { (light + deep + rem) / 3_600_000 }

    enum CodingKeys: String, CodingKey {
        case light = "total_light_sleep_time_milli"
        case deep = "total_slow_wave_sleep_time_milli"
        case rem = "total_rem_sleep_time_milli"
    }
}

private struct WorkoutCollection: Decodable {
    let records: [WorkoutRecord]
}

private struct WorkoutRecord: Decodable {
    let start: String
    let score: WorkoutScore?

    var startDate: Date? { ISO8601DateFormatter().date(from: start) }
}

private struct WorkoutScore: Decodable {
    let zoneDuration: ZoneDuration

    enum CodingKeys: String, CodingKey {
        case zoneDuration = "zone_duration"
    }
}

private struct ZoneDuration: Decodable {
    let zoneTwo: Int
    let zoneThree: Int
    let zoneFour: Int
    let zoneFive: Int

    enum CodingKeys: String, CodingKey {
        case zoneTwo = "zone_two_milli"
        case zoneThree = "zone_three_milli"
        case zoneFour = "zone_four_milli"
        case zoneFive = "zone_five_milli"
    }
}

private extension JSONDecoder {
    static var whoop: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

enum WhoopError: LocalizedError {
    case missingToken
    case unauthorized
    case invalidResponse
    case server(Int)
    case invalidCallback
    case couldNotStartOAuth
    case oauth(String)

    var errorDescription: String? {
        switch self {
        case .missingToken: "Connect WHOOP to continue."
        case .unauthorized: "Your WHOOP connection has expired. Connect it again."
        case .invalidResponse: "WHOOP returned an invalid response."
        case .server(let status): "WHOOP returned status \(status)."
        case .invalidCallback: "WHOOP did not return a valid connection ticket."
        case .couldNotStartOAuth: "The WHOOP sign-in window could not be opened."
        case .oauth(let reason): "WHOOP authorization failed: \(reason)."
        }
    }
}

enum KeychainStore {
    static func save(_ value: String, key: String) throws {
        delete(key: key)
        let status = SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: Data(value.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ] as CFDictionary, nil)
        guard status == errSecSuccess else { throw WhoopError.invalidResponse }
    }

    static func read(key: String) -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ] as CFDictionary)
    }
}

//
//  MabrookTrack — native iOS SDK (Swift)
//  Mobile measurement for TikTok app campaigns. Same wire contract as the
//  React Native package: POST https://mmp.mabrooktrack.com/app/<appKey>.
//
//  Privacy: the IDFA is read only when the user authorized tracking; email and
//  phone are hashed at MabrookTrack's edge before storage; `consent = .denied`
//  stops every send.
//

import Foundation
import UIKit
import AdSupport
import AppTrackingTransparency
import StoreKit

public enum MabrookConsent: String {
    case granted, denied, unknown
}

public struct MabrookConfig {
    /// App key from Dashboard → Agency → MMP → your app (one per platform build).
    public var appKey: String
    /// BCP-47 locale of the user, e.g. "ar-SA". Improves TikTok matching.
    public var locale: String?
    /// Start with consent already granted (skips the unknown gate).
    public var consent: MabrookConsent?
    /// Verbose logging for integration.
    public var debug: Bool = false
    /// Override the ingest origin (tests only).
    public var endpoint: String = "https://mmp.mabrooktrack.com"

    public init(appKey: String, locale: String? = nil, consent: MabrookConsent? = nil, debug: Bool = false) {
        self.appKey = appKey
        self.locale = locale
        self.consent = consent
        self.debug = debug
    }
}

public struct MabrookPurchase {
    public var value: Double
    public var currency: String
    public var orderId: String
    public var properties: [String: Any]?
    public init(value: Double, currency: String = "SAR", orderId: String, properties: [String: Any]? = nil) {
        self.value = value
        self.currency = currency
        self.orderId = orderId
        self.properties = properties
    }
}

public struct MabrookSkanValue {
    public let fine: Int
    public let coarse: String
    public let lock: Bool
}

public final class MabrookTrack {
    public static let shared = MabrookTrack()
    private init() {}

    // MARK: - State
    private var config: MabrookConfig?
    private var consent: MabrookConsent = .unknown
    private var anonId = ""
    private var sessionId = UUID().uuidString.lowercased()
    private var traits: [String: String] = [:]
    private var idfa: String?
    private var attStatus = "unknown"
    private let queue = DispatchQueue(label: "com.mabrooktrack.sdk", qos: .utility)
    private let defaults = UserDefaults.standard
    private let keys = (anon: "mbt_anon_id", installed: "mbt_installed", consent: "mbt_consent", traits: "mbt_traits")

    // MARK: - Configure

    /// Call once at app start (e.g. in `application(_:didFinishLaunchingWithOptions:)`).
    /// Sends `install` on the first launch and `app_open` afterwards.
    public static func configure(_ config: MabrookConfig) { shared.configure(config) }

    private func configure(_ cfg: MabrookConfig) {
        config = cfg
        if let c = cfg.consent { consent = c; defaults.set(c.rawValue, forKey: keys.consent) }
        else if let s = defaults.string(forKey: keys.consent), let c = MabrookConsent(rawValue: s) { consent = c }
        if let t = defaults.dictionary(forKey: keys.traits) as? [String: String] { traits = t }
        anonId = defaults.string(forKey: keys.anon) ?? {
            let id = UUID().uuidString.lowercased()
            defaults.set(id, forKey: keys.anon)
            return id
        }()
        refreshAtt()
        registerForSkan()

        let firstRun = !defaults.bool(forKey: keys.installed)
        if firstRun {
            defaults.set(true, forKey: keys.installed)
            send(["event_type": "install"])
        } else {
            send(["event_type": "app_open", "event_id": UUID().uuidString.lowercased()])
        }
        log("configured firstRun=\(firstRun) consent=\(consent.rawValue) att=\(attStatus)")
    }

    // MARK: - ATT

    /// Shows the App Tracking Transparency prompt. When the user allows, the
    /// install is re-sent with the IDFA so it can be matched to a TikTok click.
    public static func requestTrackingAuthorization(completion: ((String) -> Void)? = nil) {
        shared.requestTrackingAuthorization(completion: completion)
    }

    private func requestTrackingAuthorization(completion: ((String) -> Void)?) {
        let before = attStatus
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { [weak self] _ in
                guard let self else { return }
                self.refreshAtt()
                if before != "authorized", self.attStatus == "authorized", self.idfa != nil {
                    self.send(["event_type": "install"])
                }
                DispatchQueue.main.async { completion?(self.attStatus) }
            }
        } else {
            refreshAtt()
            completion?(attStatus)
        }
    }

    private func refreshAtt() {
        if #available(iOS 14, *) {
            switch ATTrackingManager.trackingAuthorizationStatus {
            case .authorized: attStatus = "authorized"
            case .denied: attStatus = "denied"
            case .restricted: attStatus = "restricted"
            case .notDetermined: attStatus = "not_determined"
            @unknown default: attStatus = "unknown"
            }
        } else {
            attStatus = "authorized"
        }
        let raw = ASIdentifierManager.shared().advertisingIdentifier.uuidString
        idfa = (attStatus == "authorized" && raw != "00000000-0000-0000-0000-000000000000") ? raw : nil
    }

    // MARK: - Identity & consent

    /// Attach the logged-in shopper (hashed at the edge, raw never stored).
    public static func setUser(email: String? = nil, phone: String? = nil, externalId: String? = nil) {
        let s = shared
        if let email { s.traits["email"] = email }
        if let phone { s.traits["phone"] = phone }
        if let externalId { s.traits["external_id"] = externalId }
        s.defaults.set(s.traits, forKey: s.keys.traits)
    }

    /// `.denied` stops all sends.
    public static func setConsent(_ value: MabrookConsent) {
        shared.consent = value
        shared.defaults.set(value.rawValue, forKey: shared.keys.consent)
    }

    // MARK: - Events

    /// Any event name. Standard names are mapped to TikTok's app events server-side.
    public static func track(_ name: String, properties: [String: Any]? = nil) {
        var body: [String: Any] = ["event_type": name, "event_id": UUID().uuidString.lowercased()]
        if let properties { body["properties"] = properties }
        shared.send(body)
    }

    public static func viewContent(_ properties: [String: Any]? = nil) { track("view_content", properties: properties) }
    public static func search(_ query: String, properties: [String: Any]? = nil) {
        var p = properties ?? [:]; p["query"] = query; track("search", properties: p)
    }
    public static func addToWishlist(_ properties: [String: Any]? = nil) { track("add_to_wishlist", properties: properties) }
    public static func addToCart(_ properties: [String: Any]? = nil) { track("add_to_cart", properties: properties) }
    public static func initiateCheckout(_ properties: [String: Any]? = nil) { track("initiate_checkout", properties: properties) }
    public static func addPaymentInfo(_ properties: [String: Any]? = nil) { track("add_payment_info", properties: properties) }
    public static func completeRegistration(_ properties: [String: Any]? = nil) { track("complete_registration", properties: properties) }
    public static func login(_ properties: [String: Any]? = nil) { track("login", properties: properties) }
    public static func startTrial(_ properties: [String: Any]? = nil) { track("start_trial", properties: properties) }
    public static func generateLead(_ properties: [String: Any]? = nil) { track("lead", properties: properties) }
    public static func rate(_ properties: [String: Any]? = nil) { track("rate", properties: properties) }
    public static func completeTutorial(_ properties: [String: Any]? = nil) { track("complete_tutorial", properties: properties) }
    public static func achieveLevel(_ level: Int, properties: [String: Any]? = nil) {
        var p = properties ?? [:]; p["level"] = level; track("achieve_level", properties: p)
    }
    public static func unlockAchievement(_ properties: [String: Any]? = nil) { track("unlock_achievement", properties: properties) }
    public static func spendCredits(_ value: Double, properties: [String: Any]? = nil) {
        var p = properties ?? [:]; p["value"] = value; track("spend_credits", properties: p)
    }

    /// Paid subscription started. Pass value/currency for value-based optimisation.
    public static func subscribe(value: Double? = nil, currency: String? = nil, orderId: String? = nil, properties: [String: Any]? = nil) {
        var body: [String: Any] = ["event_type": "subscribe", "event_id": UUID().uuidString.lowercased()]
        if let value { body["value"] = value }
        if let currency { body["currency"] = currency }
        if let orderId { body["order_id"] = orderId }
        if let properties { body["properties"] = properties }
        shared.send(body)
    }

    /// The money event. Deduplicated server-side on `orderId`. Syncs the SKAdNetwork value afterwards.
    public static func trackPurchase(_ purchase: MabrookPurchase) {
        var body: [String: Any] = [
            "event_type": "purchase",
            "event_id": UUID().uuidString.lowercased(),
            "value": purchase.value,
            "currency": purchase.currency,
            "order_id": purchase.orderId,
        ]
        if let p = purchase.properties { body["properties"] = p }
        shared.send(body) { ok in
            if ok { shared.syncSkanConversionValue(completion: nil) }
        }
    }

    // MARK: - SKAdNetwork

    private func registerForSkan() {
        if #available(iOS 16.1, *) {
            SKAdNetwork.updatePostbackConversionValue(0) { _ in }
        } else if #available(iOS 15.4, *) {
            SKAdNetwork.updatePostbackConversionValue(0) { _ in }
        } else {
            SKAdNetwork.registerAppForAdNetworkAttribution()
        }
    }

    /// Fetches the conversion value MabrookTrack computed for this user and
    /// hands it to SKAdNetwork. Called automatically after purchases; call it
    /// yourself after registration / login.
    public static func syncSkanConversionValue(completion: ((MabrookSkanValue?) -> Void)? = nil) {
        shared.syncSkanConversionValue(completion: completion)
    }

    private func syncSkanConversionValue(completion: ((MabrookSkanValue?) -> Void)?) {
        guard let cfg = config, consent != .denied else { completion?(nil); return }
        post(path: "/skan/cv/\(cfg.appKey)", body: ["anon_id": anonId]) { [weak self] data in
            guard let self, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["ok"] as? Bool == true,
                  let fine = json["fine"] as? Int
            else { DispatchQueue.main.async { completion?(nil) }; return }
            let coarse = json["coarse"] as? String ?? "low"
            let lock = json["lock"] as? Bool ?? false
            self.updateConversionValue(fine, coarse: coarse, lock: lock)
            DispatchQueue.main.async { completion?(MabrookSkanValue(fine: fine, coarse: coarse, lock: lock)) }
        }
    }

    private func updateConversionValue(_ fine: Int, coarse: String, lock: Bool) {
        if #available(iOS 16.1, *) {
            let c: SKAdNetwork.CoarseConversionValue = coarse == "high" ? .high : coarse == "medium" ? .medium : .low
            SKAdNetwork.updatePostbackConversionValue(fine, coarseValue: c, lockWindow: lock) { _ in }
        } else if #available(iOS 15.4, *) {
            SKAdNetwork.updatePostbackConversionValue(fine) { _ in }
        } else {
            SKAdNetwork.updateConversionValue(fine)
        }
    }

    // MARK: - Transport

    private func baseFields() -> [String: Any] {
        let device = UIDevice.current
        var f: [String: Any] = [
            "anon_id": anonId,
            "session_id": sessionId,
            "platform": "ios",
            "os": "ios",
            "os_version": device.systemVersion,
            "model": device.model,
            "att": attStatus,
            "consent": consent.rawValue,
            "ts": Int(Date().timeIntervalSince1970 * 1000),
        ]
        if let v = device.identifierForVendor?.uuidString { f["idfv"] = v }
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String { f["app_version"] = v }
        if let idfa { f["idfa"] = idfa }
        if let l = config?.locale ?? Locale.preferredLanguages.first { f["locale"] = l }
        for (k, v) in traits { f[k] = v }
        return f
    }

    private func send(_ body: [String: Any], completion: ((Bool) -> Void)? = nil) {
        guard let cfg = config else { log("track before configure()"); completion?(false); return }
        guard consent != .denied else { log("consent denied — dropped \(body["event_type"] ?? "")"); completion?(false); return }
        var payload = baseFields()
        for (k, v) in body { payload[k] = v }
        post(path: "/app/\(cfg.appKey)", body: payload) { [weak self] data in
            let ok = data != nil
            self?.log("sent \(body["event_type"] ?? "") \(ok ? "ok" : "failed")")
            completion?(ok)
        }
    }

    /// POST JSON with up to 5 attempts and exponential backoff on 5xx / network errors.
    private func post(path: String, body: [String: Any], attempt: Int = 0, completion: @escaping (Data?) -> Void) {
        guard let cfg = config, let url = URL(string: cfg.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path),
              let data = try? JSONSerialization.data(withJSONObject: body)
        else { completion(nil); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        URLSession.shared.dataTask(with: req) { [weak self] resData, res, err in
            let status = (res as? HTTPURLResponse)?.statusCode ?? 0
            if err == nil, (200..<300).contains(status) { completion(resData); return }
            if (400..<500).contains(status) { completion(nil); return } // client error: don't retry
            if attempt < 4 {
                let delay = min(30.0, 0.5 * pow(2.0, Double(attempt)))
                self?.queue.asyncAfter(deadline: .now() + delay) { self?.post(path: path, body: body, attempt: attempt + 1, completion: completion) }
            } else {
                completion(nil)
            }
        }.resume()
    }

    private func log(_ s: String) {
        if config?.debug == true { print("[MabrookTrack] \(s)") }
    }
}

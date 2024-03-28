//
//  XAttrubution.swift
//
//
//  Created by Radzivon Bartoshyk on 28/03/2023.
//

import AdSupport
import AdServices
import UIKit
import AppTrackingTransparency

public final class XAttrubution {
    
    private let key: String
    private let url: String
    private let session: URLSession
    private let userDefaults: UserDefaults
    private var userId: String?
    
    init(key: String, url: String, session: URLSession, userDefaults: UserDefaults, userId: String?) {
        self.key = key
        self.url = url
        self.session = session
        self.userDefaults = userDefaults
        self.userId = userId
    }
    
    public static func instance(key: String,
                                url: String = "https://hq.cacaomeasure.com",
                                session: URLSession = .shared,
                                userDefaults: UserDefaults = UserDefaults.standard,
                                userId: String?) -> XAttrubution {
        return XAttrubution(key: key,
                            url: url,
                            session: session,
                            userDefaults: userDefaults,
                            userId: userId)
    }
    
    public func set(userId: String?) {
        self.userId = userId
    }
    
    public func reset() {
        userDefaults.set(nil, forKey: "__aaa_x_attrubution_sent")
    }
    
    public func collect() async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { cont in
            collect { rs, err in
                if let err {
                    return cont.resume(throwing: err)
                }
                if let rs {
                    return cont.resume(returning: rs)
                }
                return cont.resume(throwing: XAttributionCollectionError())
            }
        }
    }
    
    public func collect(_ completion: (([String: Any]?, Error?) -> ())? = nil) {
        if let value = userDefaults.object(forKey: "__aaa_x_attrubution_sent") as? Bool, value {
            DispatchQueue.main.async {
                completion?(nil, XAttributionAlreadyCollectedError())
            }
            return
        }
        if #available(iOS 14.3, *) {
            Task {
                do {
                    guard var attribution = try await getAttribution() else {
                        await MainActor.run { completion?(nil, XAttributionCollectionError()) }
                        return
                    }
                    let fMethod = attribution
                    attribution.removeValue(forKey: "attribution")
                    let systemVersion = await MainActor.run { UIDevice.current.systemVersion }
                    attribution["ios_version"] = systemVersion
                    
                    if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        attribution["app_version"] = appVersion
                    }
                    
                    attribution["sdk_version"] = "3.0.0"
                    
                    let attStatus = await MainActor.run { ATTrackingManager.trackingAuthorizationStatus }
                    
                    switch attStatus {
                    case .notDetermined:
                        attribution["att_status"] = "notDetermined"
                    case .restricted:
                        attribution["att_status"] = "restricted"
                    case .denied:
                        attribution["att_status"] = "denied"
                    case .authorized:
                        attribution["att_status"] = "authorized"
                    @unknown default:
                        break
                    }
                    
                    if let userId {
                        attribution["user_id"] = userId
                    }
                    
                    let deviceType = await MainActor.run { UIDevice.current.userInterfaceIdiom }
                    if deviceType == .phone {
                        attribution["device_type"] = "phone"
                    } else if deviceType == .pad {
                        attribution["device_type"] = "tablet"
                    } else {
                        attribution["device_type"] = "other"
                    }
                    
                    attribution["idfa"] = await MainActor.run { ASIdentifierManager.shared().advertisingIdentifier.uuidString }
                    
                    let bundle = Bundle.main.bundleIdentifier
                    if let bundle {
                        attribution["bundle"] = bundle
                    }
                    
                    attribution["key"] = key
                    
                    guard var components = URLComponents(string: self.url) else {
                        await MainActor.run { completion?(nil, XAttributionCollectionError()) }
                        return
                    }
                    components.path = "/attribution"
                    
                    guard let url = components.url else {
                        await MainActor.run { completion?(nil, XAttributionCollectionError()) }
                        return
                    }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.addValue("application/json", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONSerialization.data(withJSONObject: attribution, options: .prettyPrinted)
                    
                    let (_, response) = try await self.session.data(for: request)
                    
                    await MainActor.run {
                        if let urlResponse = (response as? HTTPURLResponse), 200..<300 ~= urlResponse.statusCode {
                            finalizeCollection()
                            completion?(fMethod, nil)
                        } else {
                            completion?(nil, XAttributionCollectionError())
                        }
                    }
                } catch {
                    await MainActor.run { completion?(nil, error) }
                }
            }
        } else {
            DispatchQueue.main.async {
                completion?(nil, XAttributionCollectionError())
            }
        }
    }
    
    private func finalizeCollection() {
        userDefaults.set(true, forKey: "__aaa_x_attrubution_sent")
    }
    
    @available(iOS 14.3, *)
    private func getAttribution() async throws -> [String: Any]? {
        /**
         https://developer.apple.com/documentation/adservices/aaattribution/attributiontoken()#Attribution-payload
         */
        var urlComponents = URLComponents()
        urlComponents.scheme = "https"
        urlComponents.host = "api-adservices.apple.com"
        urlComponents.path = "/api/v1/"
        let body: Data
        do {
            let token = try AAAttribution.attributionToken()
            body = Data(token.utf8)
        } catch {
            // finalize collection no sense to proceed
            self.finalizeCollection()
            throw XAttributionTokenGenerationError(underlying: error)
        }
        
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
        
        guard let url = urlComponents.url else {
            throw XAttributionInvalidStateError(message: "Cannot construct valid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        
        var (data, response) = try await session.data(for: request)
        guard let urlResponse = (response as? HTTPURLResponse) else {
            throw XAttributionInvalidStateError(message: "Cannot construct valid response from URL request")
        }
        var statusCode = urlResponse.statusCode
        var retries: Int = 0
        
        if statusCode == 404 {
            /**
             404 signals an
             Not found. The API is unable to retrieve the requested attribution record. Tokens have a TTL of 24 hours. If the POST API call exceeds 24 hours, a 404 response returns. If your token is valid, a best practice is to initiate retries at intervals of 5 seconds with a maximum of three attempts.
             */
            // Do 3 retries with delay.
            while retries < 3 && statusCode == 404 {
                try await Task.sleep(nanoseconds: NSEC_PER_SEC*5)
                (data, response) = try await session.data(for: request)
                guard let urlResponse = (response as? HTTPURLResponse) else {
                    throw XAttributionInvalidStateError(message: "Cannot construct valid response from URL request")
                }
                statusCode = urlResponse.statusCode
                retries += 1
            }
        }
        
        if statusCode == 404 {
            throw XAttributionTokenExpiredError()
        }
        
        /**
         400 - The token is invalid.
         */
        if statusCode == 400 {
            // finalize collection no sense to proceed
            self.finalizeCollection()
            throw XAttributionInvalidTokenConditionError()
        }
        
        if 200..<300 ~= statusCode, let attribution = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any] {
            var att: [String: Any] = [:]
            attribution.forEach { key, value in att[key] = value }
            if attribution["attribution"] as? Bool == true {
                return attribution
            } else {
                throw XAttributionEmptyCollectionError()
            }
        }
        
        if statusCode == 500 {
            /**
             500 - The Apple Search Ads server is temporarily down or unreachable. The request may be valid, but you need to retry it later.
             */
            /**
             Skip for now -> allow retry later
             */
            throw XAttributionInvalidServerStateError()
        }
        
        if statusCode == 504 {
            throw XAttributionGatewayError()
        }
        throw XAttributionReachabilityError(statusCode: statusCode)
    }
}

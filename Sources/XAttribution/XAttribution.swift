//
//  XAttrubution.swift
//  
//
//  Created by Radzivon Bartoshyk on 28/03/2023.
//

import Foundation
import Alamofire
import AdSupport
import AdServices
import UIKit
import AppTrackingTransparency

public class XAttrubution {

    private let key: String
    private let url: String
    private let session: Alamofire.Session
    private let userDefaults: UserDefaults
    private var userId: String?

    init(key: String, url: String, session: Alamofire.Session, userDefaults: UserDefaults, userId: String?) {
        self.key = key
        self.url = url
        self.session = session
        self.userDefaults = userDefaults
        self.userId = userId
    }

    public static func instance(key: String,
                                url: String = "https://hq.cacaomeasure.com",
                                session: Alamofire.Session = .init(),
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

    public func collect(_ completion: ((Error?) -> ())? = nil) {
        if let value = userDefaults.object(forKey: "__aaa_x_attrubution_sent") as? Bool, value {
            return
        }
        if #available(iOS 14.3, *) {
            Task {
                do {
                    guard var attribution = await getAttribution() else {
                        return
                    }
                    attribution.removeValue(forKey: "attribution")
                    let systemVersion = await MainActor.run { UIDevice.current.systemVersion }
                    attribution["ios_version"] = systemVersion

                    if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        attribution["app_version"] = appVersion
                    }

                    attribution["sdk_version"] = "1.0.4"

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
                        return
                    }
                    components.path = "/attribution"
                    var request = try URLRequest(url: try components.asURL(),
                                                 method: .post,
                                                 headers: .init(["Content-Type": "application/json",
                                                                 "Accept": "application/json"]))

                    let jsonData = try JSONSerialization.data(withJSONObject: attribution,
                                                                    options: .prettyPrinted)
                    request.httpBody = jsonData

                    _ = await session.request(request)
                        .validate(statusCode: 200..<300)
                        .serializingData().response.data

                    userDefaults.set(true, forKey: "__aaa_x_attrubution_sent")

                    await MainActor.run { completion?(nil) }
                } catch {
                    await MainActor.run { completion?(error) }
                }
            }
        }
    }

    @available(iOS 14.3, *)
    private func getAttribution() async -> [String: Any]? {
        do {
            var urlComponents = URLComponents()
            urlComponents.scheme = "https"
            urlComponents.host = "api-adservices.apple.com"
            urlComponents.path = "/api/v1/"
            let token = try AAAttribution.attributionToken()
            let body = Data(token.utf8)
            var request = try URLRequest(url: try urlComponents.asURL(),
                                         method: .post,
                                         headers: .init(["Content-Type": "text/plain"]))
            request.httpBody = body
            guard let data = await session.request(request)
                .validate(statusCode: 200..<300)
                .serializingData().response.data else {
                return nil
            }
            guard let attribution = try JSONSerialization.jsonObject(with: data,
                                                                     options: .allowFragments) as? [String: Any] else {
                return nil
            }
            var att: [String: Any] = [:]
            attribution.forEach { key, value in att[key] = value }
            if attribution["attribution"] as? Bool == true {
                return attribution
            }
            return nil
        } catch {
            return nil
        }
    }


}

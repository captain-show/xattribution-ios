//
//  XAttribution+Errors.swift
//
//
//  Created by Radzivon Bartoshyk on 26/03/2024.
//

import Foundation

public struct XAttributionAlreadyCollectedError: LocalizedError, CustomNSError {
    public var errorDescription: String {
        "Attribution already collected"
    }
    
    public var errorUserInfo: [String : Any] {
        [NSLocalizedDescriptionKey: errorDescription]
    }
}

public struct XAttributionCollectionError: LocalizedError, CustomNSError {
    public var errorDescription: String {
        "Attribution cannot be collected"
    }
    
    public var errorUserInfo: [String : Any] {
        [NSLocalizedDescriptionKey: errorDescription]
    }
}

public struct XAttributionInvalidTokenConditionError: LocalizedError, CustomNSError {
    public var errorDescription: String {
        "Attribution token is invalid or expired"
    }
    
    public var errorUserInfo: [String : Any] {
        [NSLocalizedDescriptionKey: errorDescription]
    }
    
}

public struct XAttributionTokenGenerationError: LocalizedError, CustomNSError {
    let underlying: Error
    
    public var errorDescription: String {
        "Attribution Token cannot be collected"
    }
    
    public var errorUserInfo: [String : Any] {
        [NSLocalizedDescriptionKey: errorDescription,
        NSLocalizedFailureErrorKey: underlying.localizedDescription,
        NSLocalizedFailureReasonErrorKey: underlying]
    }
}

public struct XAttributionEmptyCollectionError: LocalizedError, CustomNSError {
    public var errorDescription: String {
        "User is not attributed"
    }
    
    public var errorUserInfo: [String : Any] {
        [NSLocalizedDescriptionKey: errorDescription]
    }
}

public struct XAttributionInvalidStateError: LocalizedError, CustomNSError {
    let message: String
    public var errorDescription: String {
        message
    }
    
    public var errorUserInfo: [String : Any] {
        [NSLocalizedDescriptionKey: errorDescription]
    }
}

public struct XAttributionReachabilityError: LocalizedError, CustomNSError {
    let statusCode: Int
    public var errorDescription: String {
        "Experiencing issues with reachability"
    }
    
    public var errorCode: Int {
        statusCode
    }
    
    public var errorUserInfo: [String : Any] {
        [NSLocalizedDescriptionKey: errorDescription, NSLocalizedFailureErrorKey: "Reachability error with code \(statusCode)"]
    }
}

public struct XAttributionTokenExpiredError: LocalizedError, CustomNSError {
    public var errorDescription: String {
        "Attribution user token is expired"
    }
    
    public var errorUserInfo: [String : Any] {
        [NSLocalizedDescriptionKey: errorDescription]
    }
}

public struct XAttributionGatewayError: LocalizedError, CustomNSError {
    public var errorDescription: String {
        "Gateway timeout"
    }
    
    public var errorUserInfo: [String : Any] {
        [NSLocalizedDescriptionKey: errorDescription]
    }
}

public struct XAttributionInvalidServerStateError: LocalizedError, CustomNSError {
    public var errorDescription: String {
        "Invalid Apple server state error"
    }
    
    public var errorUserInfo: [String : Any] {
        [NSLocalizedDescriptionKey: errorDescription]
    }
}

//
//  File.swift
//  XAttribution
//
//  Created by Radzivon Bartoshyk on 24/09/2024.
//

import Foundation

public final class XAttributionContainer: @unchecked Sendable {
    public let attribution: [String: Any]
    
    init(attribution: [String : Any]) {
        self.attribution = attribution
    }
}

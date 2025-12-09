//
//  Item.swift
//  QuickClip
//
//  Created by Brian He on 2025/12/9.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}

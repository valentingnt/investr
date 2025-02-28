//
//  Item.swift
//  investr
//
//  Created by Valentin Genest on 28/02/2025.
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

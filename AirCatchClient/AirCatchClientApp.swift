//
//  AirCatchClientApp.swift
//  AirCatchClient
//
//  Created by teja on 12/14/25.
//

import SwiftUI

@main
struct AirCatchClientApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ClientManager.shared)
        }
    }
}

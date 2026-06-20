//
//  ContentView.swift
//  Trace
//
//  Created by 승찬 on 6/16/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        CoursePlannerPage(
            coursePlanningService: DependencyContainer.live().coursePlanningService,
            locationService: DependencyContainer.live().locationService
        )
    }
}

#Preview {
    ContentView()
}

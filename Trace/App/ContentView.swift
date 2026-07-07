//
//  ContentView.swift
//  Trace
//
//  Created by 승찬 on 6/16/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        let container = DependencyContainer.live()
        CoursePlannerPage(
            coursePlanningService: container.coursePlanningService,
            locationService: container.locationService,
            courseRepository: container.courseRepository
        )
    }
}

#Preview {
    ContentView()
}

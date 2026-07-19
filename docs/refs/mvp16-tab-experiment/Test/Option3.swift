import SwiftUI
import MapKit

extension MKCoordinateRegion {
  static let applePark = MKCoordinateRegion(center: .init(latitude: 37.3346, longitude: -122.0090), latitudinalMeters: 1000, longitudinalMeters: 1000)
}

struct ContentView: View {
  @State private var showBottomSheet: Bool = true
  @State private var selection: PresentationDetent = .height(80)
  
  var body: some View {
    Map(initialPosition: .region(.applePark))
      .sheet(isPresented: $showBottomSheet) {
        BottomBarView(selection: $selection)
          .presentationDetents([.height(80), .fraction(0.6), .large], selection: $selection)
          .presentationBackgroundInteraction(.enabled)
      }
    
  }
}

/// Tab Enum
enum AppTab: String, CaseIterable {
  case people = "People"
  case devices = "Devices"
  case items = "Items"
  case me = "Me"
  
  var symbolImage: String {
    switch self {
    case .people:
      return "person.2"
    case .devices:
      return "macbook.and.iphone"
    case .items:
      return "circle.grid.2x2"
    case .me:
      return "location.slash"
    }
  }
}

struct BottomBarView: View {
  @Binding var selection: PresentationDetent
  @State private var activeTab: AppTab = .devices
  var body: some View {
    GeometryReader {
      let safeArea = $0.safeAreaInsets
      let bottomPadding = safeArea.bottom / 5
      
      VStack(spacing: 0) {
        TabView(selection: $activeTab) {
          Tab.init(value: .people) {
            IndividualTabView(.people)
          }
          
          Tab.init(value: .devices) {
            
            IndividualTabView(.devices)
          }
          Tab.init(value: .items) {
            
            IndividualTabView(.items)
            
          }
          
          Tab.init(value: .me) {
            
            IndividualTabView(.me)
            
          }
          
        }
        
        CustomTabBar()
          .padding(.bottom, bottomPadding)
//          .background(.red)
      }
      .ignoresSafeArea(.all, edges: .bottom)
    }
//    .interactiveDismissDisabled()
  }
  
  /// Individual Tab View
  @ViewBuilder
  func IndividualTabView(_ tab: AppTab) -> some View {
    ScrollView(.vertical) {
      VStack {
        HStack {
          Text(tab.rawValue)
            .font(.largeTitle.bold())
          
          Spacer(minLength: 0)
          
          Button {
            
          } label: {
            Image(systemName: "plus")
              .font(.title3)
              .fontWeight(.semibold)
              .frame(width: 30, height: 30)
          }
          .buttonStyle(.glass)
          .buttonBorderShape(.circle)
        }
        .padding(.top, 15)
        .padding(.leading, 10)
      }
      .padding(15)
      
      /// Your Tab Contents Here...
    }
    .toolbarVisibility(.hidden, for: .tabBar)
    .toolbarBackgroundVisibility(.hidden, for: .tabBar)
  }
  
  
  
  /// Custom Tab Bar
  @ViewBuilder
  func CustomTabBar() -> some View {
    HStack(spacing: 0) {
      ForEach(AppTab.allCases, id: \.rawValue) { tab in
        VStack(spacing: 6) {
          Image(systemName: tab.symbolImage)
            .font(.title3)
            .symbolVariant(.fill)
          
          Text(tab.rawValue)
            .font(.caption2)
            .fontWeight(.semibold)
        }
        .foregroundStyle(activeTab == tab ? .blue : .gray)
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .onTapGesture {
          activeTab = tab
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.top, 10)
    .padding(.bottom, 12)
  }
}

#Preview {
  ContentView()
}

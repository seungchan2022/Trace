//import SwiftUI
//import MapKit
//
//extension MKCoordinateRegion {
//  static let applePark = MKCoordinateRegion(center: .init(latitude: 37.3346, longitude: -122.0090), latitudinalMeters: 1000, longitudinalMeters: 1000)
//}
//
//struct ContentView: View {
//  /// Bottom Sheet Properties
//  @State private var showBottomSheet: Bool = true
//  @State private var sheetDetnet: PresentationDetent = .height(80)
//  
//  // 플로팅 툴바와 바텀 시트와의 거리 조절
//  @State private var sheetHeight: CGFloat = .zero
//  
//  @State private var animationDuration: CGFloat = .zero
//  @State private var toolbarOpacity: CGFloat = 1
//  
//  var body: some View {
//    Map(initialPosition: .region(.applePark))
//      .sheet(isPresented: $showBottomSheet) {
//        BottomSheetView(sheetDetent: $sheetDetnet)
//          .presentationDetents([.height(80), .height(350), .large]) // 이 부분에 대해서 직접 크기를 하드 코딩 했는데 기기마다 달라질수 있으므로 fraction 형태로 퍼센트로 가는건 어떤가
//          .presentationBackgroundInteraction(.enabled) // 이건 무슨 효과인건가?
//          .frame(maxWidth: .infinity, maxHeight: .infinity)
//          .onGeometryChange(for: CGFloat.self) {
//            max(min($0.size.height, 350), .zero) // 여기서 만약 위에서 바텀 중간 크기에 대해서 숫자가 아니라 퍼센트로 하면 이 값도 바뀌어야 하는데 어떻게 바뀔까?
//          } action: { oldValue, newValue in
//            /// Limiting the offset to 300, so that opacity effect will be visible
//            sheetHeight = min(newValue, 300)
//            
//            /// Calculating Opacity
//            let progress = max(min((newValue - 300) / 50, 1), .zero)
//            toolbarOpacity = 1 - progress
//            
//            /// Calculating Anmation Duration
//            let diff = abs(newValue - oldValue)
//            let duration = max(min(diff / 100, 0.3), .zero)
//            animationDuration = duration
//            
//          }
//          .ignoresSafeArea() // 올라갈때 거리 유지
//
//      }
//      .overlay(alignment: .bottomTrailing) {
//        BottomFloatingToolBar()
//          .padding(.trailing, 15)
//      }
//  }
//  
//  /// Bottom Floating View
//  /// 여기에 우리 프로젝트에서는 되롤리기/앞으로가기/초기화 등등 컴포넌트들을 넣으면 되지 않을까?
//  @ViewBuilder
//  func BottomFloatingToolBar() -> some View {
//    VStack(spacing: 35) {
//      Button {
//        
//      } label: {
//        Image(systemName: "car.fill")
//      }
//      
//      Button {
//        
//      } label: {
//        Image(systemName: "location")
//      }
//
//    }
//    .font(.title3)
//    .foregroundStyle(Color.primary)
//    .padding(.vertical, 20)
//    .padding(.horizontal, 10)
//    .glassEffect(.regular, in: .capsule)
//    .opacity(toolbarOpacity)
//    .offset(y: -sheetHeight)
//    .animation(.interpolatingSpring(duration: animationDuration, bounce: .zero, initialVelocity: .zero), value: sheetHeight)
//  }
//}
//
//struct BottomSheetView: View {
//  @Binding var sheetDetent: PresentationDetent
//  var body: some View {
//    Text("Hello World")
//  }
//}
//
//#Preview {
//  ContentView()
//}

import MapKit
import SwiftUI

// MARK: - Supporting Types

struct MapPin: Equatable {
    let coordinate: CLLocationCoordinate2D
    let title: String
    let color: UIColor
    let systemImage: String

    static func == (lhs: MapPin, rhs: MapPin) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
            lhs.coordinate.longitude == rhs.coordinate.longitude &&
            lhs.title == rhs.title
    }
}

final class ColoredPinAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let color: UIColor
    let systemImage: String

    init(coordinate: CLLocationCoordinate2D, title: String, color: UIColor, systemImage: String) {
        self.coordinate = coordinate
        self.title = title
        self.color = color
        self.systemImage = systemImage
    }
}

// MARK: - MapViewRepresentable

struct MapViewRepresentable: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var overlayCoordinates: [CLLocationCoordinate2D]
    var pins: [MapPin]

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.setRegion(region, animated: false)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.parent = self

        // Camera: parent가 시작한 유의미한 이동만 반영 (무한루프 방지)
        let mapCenter = uiView.region.center
        let latDiff = abs(mapCenter.latitude - region.center.latitude)
        let lonDiff = abs(mapCenter.longitude - region.center.longitude)
        if latDiff > 0.0001 || lonDiff > 0.0001 {
            uiView.setRegion(region, animated: true)
        }

        // Overlays: 좌표 수가 달라질 때만 교체
        let existingCount = uiView.overlays.compactMap { $0 as? MKPolyline }.first?.pointCount ?? 0
        if existingCount != overlayCoordinates.count {
            uiView.removeOverlays(uiView.overlays)
            if !overlayCoordinates.isEmpty {
                var coords = overlayCoordinates
                uiView.addOverlay(MKPolyline(coordinates: &coords, count: coords.count))
            }
        }

        // Annotations: 최대 2개, 변경 시 재구성
        let existing = uiView.annotations.filter { !($0 is MKUserLocation) }
            .compactMap { $0 as? ColoredPinAnnotation }
        let pinsChanged = existing.count != pins.count ||
            zip(existing, pins).contains { ann, pin in
                abs(ann.coordinate.latitude - pin.coordinate.latitude) > 0.00001
            }
        if pinsChanged {
            uiView.removeAnnotations(uiView.annotations.filter { !($0 is MKUserLocation) })
            for pin in pins {
                uiView.addAnnotation(ColoredPinAnnotation(
                    coordinate: pin.coordinate,
                    title: pin.title,
                    color: pin.color,
                    systemImage: pin.systemImage
                ))
            }
        }
    }
}

// MARK: - Coordinator

extension MapViewRepresentable {
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable

        init(parent: MapViewRepresentable) {
            self.parent = parent
        }

        // MARK: Overlay

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 6
            return renderer
        }

        // MARK: Annotation

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? ColoredPinAnnotation else { return nil }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "coloredPin")
            view.markerTintColor = pin.color
            view.glyphImage = UIImage(systemName: pin.systemImage)
            return view
        }

        // MARK: Camera

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            parent.region = mapView.region
        }
    }
}

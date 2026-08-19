//
//  PlaceNameResolver.swift
//  Sajadah
//

import CoreLocation
import Foundation
import MapKit

/// Turns a coordinate into something short enough for a popover header, like "Toronto, ON".
///
/// Uses MapKit's reverse geocoding rather than `CLGeocoder`, which is deprecated as of
/// macOS 26. Returns a `String` rather than a map item on purpose: nothing outside this file
/// needs the other forty fields, and a `String` crosses actor boundaries freely.
@MainActor
enum PlaceNameResolver {
    static func shortName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else {
            return nil
        }

        // `cityWithContext` is already "Toronto, ON" — no assembling required.
        return item.addressRepresentations?.cityWithContext
            ?? item.addressRepresentations?.cityName
            ?? item.addressRepresentations?.regionName
            ?? item.address?.shortAddress
    }
}

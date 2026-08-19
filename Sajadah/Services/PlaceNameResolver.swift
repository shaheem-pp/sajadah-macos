//
//  PlaceNameResolver.swift
//  Sajadah
//

import CoreLocation
import Foundation
import MapKit

/// Turns a coordinate into something short enough for a popover header, like "Toronto, ON".
///
/// Two implementations, because the API changed under us. macOS 26 deprecated `CLGeocoder` in
/// favour of `MKReverseGeocodingRequest`; macOS 15 has only the former. Both return a `String`
/// rather than a placemark or map item on purpose: nothing outside this file needs the other
/// forty fields, and a `String` crosses actor boundaries freely.
@MainActor
enum PlaceNameResolver {
    static func shortName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        if #available(macOS 26, *) {
            return await modernShortName(for: location)
        } else {
            return await legacyShortName(for: location)
        }
    }

    @available(macOS 26, *)
    private static func modernShortName(for location: CLLocation) async -> String? {
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

    /// Marked deprecated to match `CLGeocoder` itself, which is what stops the macOS 26 SDK
    /// warning about every call below. The annotation documents the situation rather than
    /// discouraging use: on macOS 15 this is the only reverse geocoder there is.
    @available(macOS, deprecated: 26.0, message: "macOS 26 supersedes this with MKReverseGeocodingRequest.")
    private static func legacyShortName(for location: CLLocation) async -> String? {
        guard let place = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return nil
        }

        // Assembled by hand to match `cityWithContext` above, so the header reads identically
        // whichever path produced it. `administrativeArea` is already abbreviated ("ON", "CA")
        // wherever the region uses abbreviations.
        let city = place.locality ?? place.subAdministrativeArea
        let region = place.administrativeArea ?? place.country

        return switch (city, region) {
        // City-states and single-city regions report the same name twice — Mecca sits in
        // Mecca Province, and "Mecca, Mecca" reads as a bug rather than a location.
        case let (city?, region?) where city == region: city
        case let (city?, region?): "\(city), \(region)"
        case let (city?, nil): city
        case let (nil, region?): region
        case (nil, nil): place.name
        }
    }
}

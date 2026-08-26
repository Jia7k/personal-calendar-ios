import MapKit

@MainActor
protocol EventLocationMapsOpening {
    func open(location: String) async
}

@MainActor
struct SystemEventLocationMapsOpener: EventLocationMapsOpening {
    func open(location: String) async {
        let query = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first else { return }
        _ = MKMapItem.openMaps(with: [item])
    }
}

@MainActor
struct NoopEventLocationMapsOpener: EventLocationMapsOpening {
    func open(location: String) async {}
}

import MapKit
import SwiftUI

struct ContentView: View {
    @State private var probe = CompleterProbe()

    var body: some View {
        @Bindable var probe = probe
        ScrollView {
            VStack(spacing: 24) {
                ProbeMapView(mapView: probe.mapView)
                    .frame(height: 240)
                    .clipShape(.rect(cornerRadius: 12))

                Toggle("Show user location", isOn: $probe.showsUserLocation)

                Toggle("regionPriority = .required", isOn: $probe.setsRequiredRegionPriority)
                    // Applied when Start makes the completer, so fixed while there's one.
                    .disabled(probe.completer != nil)

                VStack(spacing: 4) {
                    Text(probe.failureCount, format: .number)
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.default, value: probe.failureCount)
                    Text("completer(_:didFailWithError:) calls")
                        .font(.headline)
                }

                if let lastError = probe.lastError {
                    Text(lastError)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    if probe.completer == nil {
                        probe.start()
                    } else {
                        probe.stop()
                    }
                } label: {
                    Text(probe.completer == nil ? "Start" : "Stop")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Start creates an MKLocalSearchCompleter and, with the switch on, sets regionPriority = .required, without ever setting a query. That setting alone starts a search, and the loop needs it. Stop cancels and releases the completer.")
                    Text("While the map above isn't showing the user's location, the completer's failed search is retried about four times a second, indefinitely, and MapKit soon throttles the app.")
                    Text("Turn on Show user location and the failures stop immediately, even mid-run. Turn it off and the next run loops again.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .task {
            probe.requestLocationAccess()
        }
    }
}

/// Shows the probe's map view, which lives as long as the app, rather than making one per update.
private struct ProbeMapView: UIViewRepresentable {
    let mapView: MKMapView

    func makeUIView(context: Context) -> MKMapView {
        mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {}
}

#Preview {
    ContentView()
}

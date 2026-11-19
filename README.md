# CompleterRetryLoop

Sample project for a MapKit bug in iOS 27.2: an `MKLocalSearchCompleter` with `regionPriority = .required` — which starts a search even though it's never given a query — retries that failed search about every 250 ms, forever, once an `MKMapView` with a nonzero size has existed in the process — even one that's never shown and has since been deallocated — unless that map view shows the user's location. Within a minute the app is throttled by MapKit's 100-requests-per-minute limit, which blocks its real searches.

See [FeedbackReport.md](FeedbackReport.md) for the full report, steps, and analysis.

## Running it

1. Open `CompleterRetryLoop.xcodeproj` and run on an iOS 27 device or Simulator (choose a team under Signing for a device).
2. Allow location access.
3. Leave **Show user location** off and tap **Start**. The counter of `completer(_:didFailWithError:)` calls climbs about four times a second; the console logs each failure.

The map at the top exists for the app's whole life; **Show user location** sets its `showsUserLocation`. **regionPriority = .required** chooses whether Start sets that on the completer.

| regionPriority = .required | Show user location | Result |
|---|---|---|
| On | Off | Loops |
| On | On | One failure |
| Off | Either | No failures: the completer stays idle |

Turning the switch on stops the failures immediately, even mid-run; turning it off makes the next run loop again. Without any map view at all, a fresh launch fails once; but once a map view that doesn't show the user's location has existed, completers keep looping even after it's deallocated.

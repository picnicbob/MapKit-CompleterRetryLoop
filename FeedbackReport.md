# MKLocalSearchCompleter with regionPriority = .required retries a failed search every ~250 ms forever once an MKMapView has existed, throttling the app's MapKit requests

**Area:** MapKit
**Platform:** iOS 27.2 (Simulator and device)
**Attachments:** CompleterRetryLoop sample project, console log of a looping run, sysdiagnose

## Summary

An `MKLocalSearchCompleter` with `regionPriority = .required` that's never given a query keeps sending autocomplete requests about four times a second, indefinitely, if an `MKMapView` with a nonzero size has existed anywhere in the process. Setting `regionPriority = .required` is what starts the search: until then the completer is idle, and it's required for the loop. The map view doesn't have to be on screen or in a window or view hierarchy, and it doesn't have to exist any more: once one has been created, every completer made afterwards loops, even after the map view is released and deallocated. A map view that shows the user's location (`showsUserLocation = true`) doesn't cause it, and turning `showsUserLocation` on stops later completers from looping; turning it off again brings the loop back.

Within a minute the app exceeds MapKit's limit of 100 place requests per 60 seconds (`GEOErrorDomain -3`), so the app's real searches are throttled too. The console also logs `[MKCoreLocationProvider] CLLocationManager(...) did fail with error: Error Domain=kCLErrorDomain Code=0` at the same rate, followed by `[GEOXPC] Throttled "PlaceRequest.REQUEST_TYPE_AUTOCOMPLETE" request` faults.

## Steps to reproduce

Using the attached sample:

1. Launch the app and allow location access.
2. Leave "Show user location" off and tap Start. (The sample shows an `MKMapView` at the top of the screen for its whole life.)
3. Watch the counter of `completer(_:didFailWithError:)` calls.

Equivalent code:

```swift
let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 300)) // kept, never shown
let completer = MKLocalSearchCompleter()
completer.delegate = self
completer.regionPriority = .required // required: starts a search, though no queryFragment is ever set
```

## Expected

Setting `regionPriority` shouldn't start a search, so no requests, or at most one, since no query fragment has been set.

## Actual

- `isSearching` is true immediately after setting `regionPriority = .required`, though `queryFragment` is empty.
- `completer(_:didFailWithError:)` is called about every 250 ms indefinitely, with `MKErrorDomain 5 {MKErrorGEOError=-10}`, then `MKErrorDomain 3 {MKErrorGEOError=-3}` once throttled.
- In a fresh launch with no map view, or with "Show user location" on, there's a single failure and no retries — itself unexpected, since there's no query.
- Without `regionPriority = .required` (the sample's switch off), the completer stays idle: no requests and no delegate calls, even while the map view isn't showing the user's location.

## Which map views cause it

Each run from a fresh launch, with a 300×300 `MKMapView` and the completer above (`regionPriority = .required`):

| `showsUserLocation` | In the key window, on screen | Result |
|---|---|---|
| false | no | Loops |
| true | no | One failure, no loop |
| false | yes | Loops |
| true | yes | One failure, no loop |

Being on screen makes no difference; showing the user's location prevents the loop.

## The map view's effect outlasts it

In an earlier version of the sample, which created the map view per run, releasing it (confirmed deallocated with a weak reference) didn't help: every completer created afterwards still looped, until the app was relaunched or a map view showed the user's location. So a control run without a map view must start from a fresh launch.

Toggling `showsUserLocation` between runs, without relaunching, switches the loop off and on. Turning it on while a completer is looping stops the failures immediately.

## Analysis

From the iOS 27.2 MapKit binary:

- Setting `regionPriority = .required` starts a search with an empty fragment: `isSearching` is true right afterwards, and `_fireRequest` runs. Without that setting the completer stays idle.

- `__38-[MKLocalSearchCompleter _fireRequest]_block_invoke_4`, the request's completion, calls `_handleError:forTicket:` (which reports `completer:didFailWithError:`), then calls `_schedulePendingRequest` whenever `_timer` is non-nil.
- `_fireRequest` cancels `_timer`, then asks `+[MKLocationManager sharedLocationManager]` for a one-time location (`singleLocationUpdateWithHandler:`). When a location arrives without error, its handler (`__38-[MKLocalSearchCompleter _fireRequest]_block_invoke`) calls `_markDirty`, which schedules a new `_timer` via `_markDirtyAndScheduleRequestWithTimeToNextRequest:`.
- Caught in the debugger: `MKCoreLocationProvider locationManager:didUpdateLocations:` → `MKLocationManager _reportLocationStatus:` → `MKLocationManagerSingleUpdater locationManagerUpdatedLocation:` → `_fireRequest` block → `_markDirtyAndScheduleRequestWithTimeToNextRequest:`. At the next failure, `_timer` was set and `_dirty` was 1.

So whenever the one-time location arrives while the request is in flight, the failure finds a timer and reschedules, and each retry asks for another location — forever. Once an `MKMapView` has existed, MapKit's shared location manager delivers that location in time on every attempt, apparently because of state that remains in the shared location manager after the map view is gone.

Why `showsUserLocation` prevents it is inferred, not traced: before asking for the one-time update, `_fireRequest` checks `-[MKLocationManager hasLocation]` and `-[MKLocationManager isLastLocationStale]`. A map view showing the user's location keeps the shared location manager updating, so its location is presumably always fresh, the completer uses it directly, and no one-time update arrives mid-request to schedule a retry.

## Workaround

Call `cancel()` on the completer right after setting `regionPriority = .required`. Requests made by setting `queryFragment` afterwards work normally. Showing the user's location in a map view also avoids it, where that suits the app.

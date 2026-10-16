//
// Copyright © Agulhas Labs
//

import Foundation

/// Computes the value a figure should read, outside the app (Brief §2.3): `expected(figure-id, window) -> value + attribution`.
///
/// A protocol rather than a HealthKit feature: the implementation is whatever data source the app reads. SimWalk's own is `CommandOracle`, an external command speaking JSON lines, so nothing HealthKit- or Agulhas-specific enters the tool.
public protocol ValueOracle {
    /// One answer per request, in request order — asked all at once, so an implementation can answer a whole walk in one pass over its data.
    func answers(to requests: [OracleRequest]) -> [OracleAnswer]
}

// SPDX-License-Identifier: GPL-3.0-or-later

@preconcurrency import TripKit

// Eindeutige Namen für TripKit-Typen, die in FahrplanKit mit eigenen Typen kollidieren.
public typealias TKLocation = Location
public typealias TKLocationPoint = LocationPoint
public typealias TKDeparture = Departure
public typealias TKStop = Stop
public typealias TKStopEvent = StopEvent
public typealias TKTrip = Trip
public typealias TKPublicLeg = PublicLeg
public typealias TKIndividualLeg = IndividualLeg
public typealias TKLine = Line
public typealias TKProduct = Product
public typealias TKTripOptions = TripOptions
public typealias TKWalkSpeed = WalkSpeed
public typealias TKLoadFactor = LoadFactor
public typealias TKNetworkProvider = NetworkProvider
public typealias TKJourneyContext = QueryJourneyDetailContext
public typealias TKEfaJourneyContext = EfaJourneyContext
public typealias TKLocationType = LocationType
public typealias TKFare = Fare

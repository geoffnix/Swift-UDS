# Swift-UDS

Swift-UDS is an implementation of the [Unified Diagnostic Services](https://en.wikipedia.org/wiki/Unified_Diagnostic_Services), written in [Swift](https://www.swift.org).

## Introduction

This library implements various diagnostic protocols originating in the automotive space, such as:

* __ISO 14229:2020__ : Road vehicles — Unified diagnostic services (UDS)
* __ISO 15765-2:2016__ : Road vehicles — Diagnostic communication over Controller Area Network (DoCAN)
* __SAE J1979:201408__ : Surface Vehicle Standard – (R) E/E Diagnostic Test Modes (OBD2)
* __GMW 3110:2010__ : General Motors Local Area Network Enhanced Diagnostic Test Mode Specification (GMLAN)

## How to use

This is an SPM-compatible package for the use with Xcode (on macOS) or other SPM-compliant consumer (wherever Swift runs on). See the example executable target for a quick primer.

## Motivation

In 2016, I started working on automotive diagnostics. I created the iOS app [OBD2 Expert](https://apps.apple.com/app/obd2-experte/id1142156521), which by now has been downloaded over 500.000 times. I released the underlying framework [LTSupportAutomotive](https://github.com/mickeyl/LTSupportAutomotive), written in Objective-C, as open source.

In 2021, I revisited this domain and have been contracted to implement the UDS protocol on top of the existing library.
Pretty soon though it became obvious that there are [too many OBD2-isms](https://github.com/mickeyl/LTSupportAutomotive/issues/35#issuecomment-808062461) in `LTSupportAutomotive` and extending it with UDS would be overcomplicated.
Together with my new focus on Swift, I decided to start from scratch as the library [CornucopiaUDS](https://github.com/Cornucopia-Swift/CornucopiaUDS).

By August 2021, the first working version of `CornucopiaUDS` was done and used in the automotive tuning app [TPE-Tuning](https://apps.apple.com/app/tpe-tuning/id1561470949).
From the start though, the plan has been to make this a "transitioning" library, in particular because of the forthcoming
concurrency features debuting in Swift 5.5: Communication with external hardware is asynchronous by nature, so `async`/`await`
and the `actor` abstractions will be a natural fit.

This library is supposed to become the successor of both `LTSupportAutomotive` and `CornucopiaUDS`. Due to Swift 5.5, on Apple
platforms it comes with a relatively high deployment target – limiting you to iOS 15, tvOS 15, watchOS 8, and macOS 12 (and above).

## Software

This package contains three modules, `Swift_UDS`, `Swift_UDS_Adapter`, and `Swift_UDS_Session`:

* `Swift_UDS` contains common UDS and OBD2 definitions, types, and structures,
* `Swift_UDS_Adapter` contains generic support for OBD2 adapters with a reference implementation for serial adapters and a thread-safe `actor` pipeline,
* `Swift_UDS_Session` contains both a UDS and a OBD2 session abstraction for higher level UDS and OBD2 calls.

## Hardware

This library is hardware-agnostic and is supposed to work with all kinds of OBD2 adapters. The reference adapter implementation is for generic serial streaming adapters, such as

* ELM327 (and its various clones), **only for OBD2, the ELM327 is NOT suitable for UDS**
* STN11xx-based (e.g., OBDLINK SX),
* STN22xx-based (e.g., OBDLINK MX+, OBDLINK EX, OBDLINK CX),
* WGSoft.de UniCarScan 2100 and later,

Support for direct CAN-adapters (such as the Rusoku TouCAN) is also on the way.

For the actual communication, I advise to use [CornucopiaStreams](https://github.com/Cornucopia-Swift/CornucopiaStreams), which transforms WiFi, Bluetooth Classic, BTLE, and TTY into a common stream-based interface.

## Status

Currently: **Work in Progress, nothing usable yet**

- August 2021: Nothing there yet, I'm still planning.
- September 2021: Hitting real hard blocks with the state of `async`/`await` in the yet-to-be-released Swift 5.5.
- October 2021: Some concurrency issues have been solved in the meantime, hence starting to (re)implement the first bunch of classes.

### Bus Protocols

Although I have successfully used this library as the base for an ECU reprogramming app, it has _not_ yet been battle-tested. Moreoever, while it has been designed
with all kind of bus protocols in mind, support for CAN is most advanced. Older bus protocols, such as K-LINE, J1850, and ISO9141-2 should be working at least with OBD2,
but your mileage might vary.

### UDS

UDS is about 50% done – I have started with the necessary calls to upload (TESTER -> ECU) new flash firmwares. The other way is not done yet.
There is limited support for the diagnostic commands from KWP and GMLAN and I'm not against adding more, but it's not a personal preference.

### OBD2

Although I plan to implement the full set of OBD2 calls, the primary focus has been on UDS. I have started to implement a bunch of OBD2 calls to lay out the path for contributors, but did not have time yet to do more. You might want to have a look at the [messageSpecs](https://github.com/Automotive-Swift/Swift-UDS/blob/e2bfbd64dfaefe98375952972f338f1c0089389e/Sources/Swift-UDS/OBD2/OBD2.swift#L102), if you want to help.
Note that this might be an appropriate case for a [`@ResultBuilder`](https://github.com/apple/swift-evolution/blob/main/proposals/0289-result-builders.md).

## Contributions

Feel free to use this under the obligations of the MIT. I welcome all forms of contributions. Stay safe and sound!


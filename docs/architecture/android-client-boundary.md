# Android client boundary

Status: Step 38 Android target baseline; no APK/AAB is released

The shared UI package exposes an Android target contract with the frozen
distribution forms (`apk` and `aab`), Android Keystore credential storage, no
authentication tokens in `localStorage`, and `QUEUED` as the only offline
approval state. Android review uses the same mobile opportunity order as
iPhone/iPad.

The boundary validates a reverse-domain application ID but does not select a
store package, sign an artifact, register push delivery, or grant independent
recovery authority. Those remain later release and device-integration work.

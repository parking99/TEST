# IOSLocationTracker

Open `IOSLocationTracker.xcodeproj` in Xcode on a Mac. In **Signing & Capabilities**, select your Apple ID team, then add **Background Modes** and enable **Location updates**. Connect the iPhone, choose it as the run destination, and press Run.

The default Google Apps Script endpoint is already configured. It sends `{ "latitude": Double, "longitude": Double }` and expects `{ "alarm_state": "ON" | "OFF" }`.

# App Review — audio background mode

Kohi declares `UIBackgroundModes: audio` so a brew voice note can keep recording while the screen is locked during a timed brew.

- Recording starts from the guided brew timer (`GuidedBrewView`), never from the rest of the app.
- While it runs, the Lock Screen Live Activity shows that a note is being recorded.
- Recording ends with the brew (Stop, or the last step).
- Speech is recognised on-device after the brew. The audio never leaves the phone, and is deleted after transcription unless the user turns on **Keep brew recordings** in Profile › Features.

# App Review — audio background mode

Kohi declares `UIBackgroundModes: audio` so a brew voice note can keep recording while the screen is locked during a timed brew.

- Recording starts from the guided brew timer (`GuidedBrewView`), never from the rest of the app.
- While it runs, the Lock Screen Live Activity shows that a note is being recorded.
- Recording ends with the brew (Stop, or the last step).
- Speech is recognised on-device after the brew first.
- The audio leaves the phone only while **Share dictations to improve Kohi** is on in Profile › Features (on by default, can be turned off). Then it is kept in Kohi's private storage, and sent through Kohi's server to a transcription provider so the brew steps can be read: Google Gemini, ElevenLabs Scribe or OpenAI, depending on the pipeline in use. In TestFlight builds, testers who turn on **Compare transcriptions** send the same note to each of them, to compare the readings.
- With sharing off, the audio never leaves the phone, and is deleted after transcription unless the user turns on **Keep brew recordings** in Profile › Features.

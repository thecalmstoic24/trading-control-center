# Preview 24.2: Windows PowerShell curl compatibility fix

Update affected VM agents only. The Preview 24 Control Center remains compatible; no Control Center update is required. Agent protocol identifier stays Preview 24.

- Corrects the unsupported StandardInputEncoding property used in Preview 24.1.
- Sends the token and JSON body as UTF-8 bytes through the standard-input stream using .NET Framework-compatible APIs. Tokens remain absent from process arguments and temporary files.
- Preserves Airtable curl fallback, HTTP failure handling, certificate verification and remembered transport preference.
- Tested on the available PowerShell runtime with a fake curl process, including Unicode JSON and failure cases. The actual Windows PowerShell 5.1 VM login still needs verification.

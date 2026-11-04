# Watch language and identity boundary

The Apple Watch app supports device-local System, Simplified Chinese, and English preferences through the official `AgentIdentityLocalization` store. Unsupported system languages use English. It does not expose an account-inheritance choice or modify the paired phone’s account preferences.

The current Watch login is a device credential, not a User Center session:

- `FamilyReward.Api/Program.cs`, `WatchDeviceBinding`: device ID, child ID, family-group ID, child profile key, parent application-user ID, token hash, device name, and platform. There is no authenticated User Center subject.
- `RequireWatchDeviceBinding` authenticates the token against `watch_device_bindings` and an active `children` record.
- A child profile may optionally be associated with `app_user_profiles.role = 'child'` and a `unified_user_id`; `EnsureChildAppUserProfile` maintains that business association. The device token itself does not grant a User Center session or authority to impersonate that user.
- The current backend uses User Center JWT/cookie authentication, native login, and feedback SDKs. The administrative user-directory adapter forwards the current signed-in user’s Authorization/Cookie. No official device-token-to-delegated-user-session contract is configured here.

Acceptance boundary: account-global preferences apply to clients authenticated to User Center. Extending account-global inheritance to this Watch’s bound child requires an official authenticated/delegated User Center capability that verifies the child association and grants only language-preference access. A parent token, guessed token exchange, or a bare profile-key lookup is not a substitute. This optional account association is not implemented by the language UI change.

The iPhone/iPad app uses its verified User Center subject and account-scoped cached preferences. The share extension reads only the selected effective language from the existing app group; authentication tokens are not copied into that group.

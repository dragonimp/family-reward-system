# Keep the original public domain

The independent application ID is `linko-moment.ai`; all new Moment clients, Web entry and callbacks stay on `https://happylife.ai.impx.net`. Native versions 1.3.61 (261) and Android 1.0.30 (39) supersede the temporary xmkurt-origin build. The original app registration and legacy token audience remain accepted; native session namespaces still separate the independent app from the original identity.

This supersedes only the edge-file part of `moment-identity-switch-20261114-v1`. The one-way Moment-to-Social SSO rule remains required. Do not rewrite the predecessor journal/checksum. The explicit script validates its exact applied edge hash and the original private backup, restores only that file, validates Nginx and gracefully reloads it, with its own one-time immutable receipt and rollback backup. It is never invoked at application startup. An old predecessor verification will report the intentionally superseded edge hash; use the superseding receipt for current edge ownership.

User Center's separate callback-host migration authorizes the unchanged primary domain for the new app. Atlas's separate Web-entry migration restores the original invitation URL. No account or business data is migrated. API, iOS, Android and Watch acceptance remain separately recorded.

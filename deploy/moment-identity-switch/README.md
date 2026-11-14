# Independent Moment login switch

New native clients and the `happylife.ai.xmkurt.com` website use User Center application `linko-moment.ai`. The `happylife.ai.impx.net` hostname retains application `happylife.ai` for installed legacy clients. Application rows, old roles, credentials and sessions are not overwritten. Native secure-session namespaces differ, so a cached legacy token is not silently reused for the new app.

The authenticated social gateway selects the source application from the already verified principal, accepts only the two configured application IDs, and caches each audience independently. A scoped User Center configuration rule permits only `linko-moment.ai` to exchange into the existing `linko.ai` service. No reverse grant or role copy is created.

Publish this source and the application release before executing `apply.py preflight`, then `apply.py apply` from the published deployment folder. The explicit deployment step records immutable script/config checksums, original hashes, private backups, planned/applied state and compare-and-swap checks. It never runs at application startup. Nginx is validated before graceful reload; failure restores the changed files. An interrupted prepared receipt must be inspected, not replayed. Restart User Center only through its Atlas idle-aware application operation, then verify the live new-host login context and original-host context separately.

Rollback before native distribution: switch the family API to its previous Atlas release and restore the saved edge/environment files via a new audited operation; do not alter or delete the independent application registration. After distribution, preserve the new callback host and token audience until installed clients have been accounted for.

APNs routing is separate from login. The current legacy `happylife.ai` application has no APNs application mapping in the inspected User Center runtime, so this operation does not invent a new mapping or copy provider credentials. Real push delivery remains a separate acceptance gate.

# Security Policy

## Sensitive Data Handling

This project must not receive sensitive secrets in Git history.

- Do not commit `config/config.local.json`.
- Do not commit account/password, cookies, tokens, or raw packet captures.
- Do not open issues containing personal credentials.

## Credential Storage

Use Windows Credential Manager with target name `CampusPortalAuth`.

Example:

```powershell
cmdkey /generic:CampusPortalAuth /user:YOUR_STUDENT_ID /pass:YOUR_PASSWORD
```

## Reporting a Vulnerability

Open a private security report if available in your platform.
If private reporting is unavailable, open a minimal public issue without sensitive details.

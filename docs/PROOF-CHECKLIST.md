# Proof & screenshots

**All commands (when, where, order, screenshots) are in one file:**

→ [`docs/COMMANDS-REFERENCE.txt`](COMMANDS-REFERENCE.txt)

Open **Section A** for the full demo order.  
Open **Section H** for the screenshot checklist.  
**Last script to run:** `prove_emqx_cluster.ps1` (Section A, Step 8).

**Security validation (recommended after verify):** `validate_security.ps1` — security groups,
ports 1883 / 8883 / 18083, MQTT over TLS and ACM. See Section I in
[`COMMANDS-REFERENCE.txt`](COMMANDS-REFERENCE.txt) and [`docs/security-validation.md`](security-validation.md).

**Authentication validation:** `validate_authentication.ps1` — username/password auth, built-in
backend, 2K authenticated clients with success rate and latency metrics. See
[`docs/authentication-validation.md`](authentication-validation.md).

**Auth during scale-out:** `validate_auth_scale_out.ps1` — authenticated clients held while ASG
scales; validates new nodes accept auth with zero failure increase.

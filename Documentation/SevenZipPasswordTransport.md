# 7zz password transport security checkpoint

Tested with official 7zz 26.02 on macOS arm64, 2026-08-17.

## Findings

- **[DOC]** The bundled 7-Zip manual documents `-p{password}` and says an interactive password is requested when no password is supplied.
- **[TEST]** A running command containing `-pFAKE_PASSWORD_VISIBILITY_PROBE` was visible verbatim through same-user `ps -axo command=`. Passwords in argv are therefore prohibited.
- **[TEST]** `printf 'FAKE_TEST_PASSWORD\n' | 7zz t -p encrypted.7z` did not authenticate. In this build, explicit `-p` behaved as an empty password rather than consuming an ordinary stdin pipe.
- **[TEST]** Omitting the `-p` switch while attached to a PTY produced `Enter password:` and accepted the fake password.
- **[TEST]** The generic test PTY echoed typed input. A production PTY must disable `ECHO` on the slave with `termios` before the child starts; neither the PTY input nor prompt transcript may enter diagnostics.

## Required production design

Credential-free operations use the normal structured-argument `Process` runner. Credentialed operations use a dedicated POSIX PTY launcher:

1. create a PTY master/slave pair;
2. disable terminal echo on the slave before spawn;
3. spawn 7zz directly—never through a shell—with the slave as its controlling terminal and without any password argument or environment variable;
4. detect the bounded password prompt state, write the password bytes plus newline to the master, then immediately discard the credential buffer;
5. separate progress/diagnostic capture from the secret exchange and redact all command representations;
6. propagate cancellation and always reap the child;
7. contract-test success, incorrect password, cancellation, forced termination, prompt fragmentation, absence from argv, and absence from captured diagnostics.

## Implemented result

- **[DOC+TEST]** Production uses `openpty` followed by direct `posix_spawn`; no Swift code runs between `fork` and `exec`.
- **[TEST]** The slave has `ECHO` and `ECHONL` disabled before spawn. Canonical mode is retained because 7zz expects line-oriented terminal input.
- **[TEST]** Extraction/testing prompt when `-p` is omitted. Encrypted creation prompts once when the argument is exactly `-p`; 7zz 26.02 did not request confirmation.
- **[TEST]** Fragmented prompt detection, bounded terminal capture, UTF-8 fragments, encrypted create/test/extract, incorrect passwords, cancellation, forced kill, and live argv inspection pass.
- **[TEST]** The distinctive fake secret is absent from captured output, diagnostics, descriptions, and live child argv.
- **[INFERENCE]** `SecretBytes` uses immutable `Data` to minimize accidental textual copies, but Swift/Foundation provide no defensible guarantee that all transient copies are zeroized. The implementation makes no such claim and keeps credential lifetime scoped to the open session/operation.

Secure setup failure is fatal for the credentialed operation and never falls back to argv, environment, or disk transport.

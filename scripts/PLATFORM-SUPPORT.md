# Plattformstatus

## Verifiziert

### Linux

Status: getestet

Testsystem:

```text
Linux ubuntu 7.0.0-27-generic #27-Ubuntu SMP PREEMPT_DYNAMIC Thu Jun 18 19:13:49 UTC 2026 x86_64 GNU/Linux
```

Getesteter Installationsweg:

```bash
./install.sh --backend cpu
```

## Noch nicht verifiziert

### Windows 10

Status: nicht getestet

Geplanter Installationsweg aus Git Bash:

```bash
./install.sh --backend cuda
```

### Windows 11

Status: nicht getestet

Geplanter Installationsweg aus Git Bash:

```bash
./install.sh --backend cuda
```

## Regel

Ein System gilt erst als getestet, wenn Setup, Checkout, Cargo-Build, Installation und `bitshit --version` erfolgreich durchgelaufen sind. Hardware-Erkennung allein gilt nicht als erfolgreicher Plattformtest.

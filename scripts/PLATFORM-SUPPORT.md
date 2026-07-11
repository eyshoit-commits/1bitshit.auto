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

## Aktiver Test

### Windows 10 Pro N

Status: wird getestet, noch nicht erfolgreich verifiziert

Testsystem:

```text
Edition: Windows 10 Pro N
Version: 22H2
Installiert am: 15.05.2026
Betriebssystembuild: 19045.6466
```

Testweg aus Git Bash:

```bash
./install.sh --backend cuda
```

## Noch nicht verifiziert

### Windows 11

Status: nicht getestet

Geplanter Installationsweg aus Git Bash:

```bash
./install.sh --backend cuda
```

## Regel

Ein System gilt erst als getestet, wenn Setup, Checkout, Cargo-Build, Installation und `bitshit --version` erfolgreich durchgelaufen sind. Hardware-Erkennung allein gilt nicht als erfolgreicher Plattformtest.

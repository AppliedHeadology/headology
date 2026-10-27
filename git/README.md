# 🛑 Git Headology: Automated Exasperation

Typing out your misery for every minor bug fix is an inefficient use of time. This repository contains a Git hook and a localized fortune database to automate the process of complaining to the machine. 

It intercepts lazy, bare-minimum commit prefixes (e.g., `fix:`) and forcefully expands them into lore-accurate, deeply cynical commit messages.

## 🗂️ The Bureaucracy (Installation)

Do not track this directly in the target repository's Git history unless you want your coworkers asking questions. Install it locally.

**1. Copy the infrastructure**
Place the `commit-msg` hook into the target repository's `.git/hooks/` directory and ensure it is executable.
```bash
cp commit-msg /path/to/repo/.git/hooks/commit-msg
chmod +x /path/to/repo/.git/hooks/commit-msg

```

**2. Establish the database**
Copy the `fortunes` directory into the root of the target repository (or modify the hook's `FORTUNE_DIR` path to point to a global hidden directory like `~/.fortunes/`).

**3. Compile the fortunes**
The `fortune` command requires a compiled `.dat` file to read the strings. If you add new complaints to the text files, you must recompile them using `strfile`:

```bash
cd fortunes
strfile chore chore.dat
strfile docs docs.dat
strfile feat feat.dat
strfile fix fix.dat
strfile init init.dat
strfile refact refact.dat

```

## ⚙️ Usage (Complaining to the Machine)

Commit your code using a standard prefix. Do not bother writing a full message.

```bash
git commit -m "fix:"

```

The hook will intercept the prefix, consult the database, overwrite the message, and echo the final result to the terminal so you know exactly how you feel about the code today.

```text
🛑 Deadlock Vimes dictates:
fix: Applied percussive maintenance to the routing table.

```

## 📜 Standing Orders

If the fortunes fail to load, the hook will gracefully fall back to the bare prefix. The system assumes failure is the default state and plans accordingly.

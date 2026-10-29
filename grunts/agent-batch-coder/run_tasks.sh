#!/usr/bin/env bash
set -uo pipefail

export GIT_PAGER=cat
export PAGER=cat

# Argument 1: the agent's scratch directory. No argument means /tmp/batch-coder-tasks, which is where lost things go.
TASK_DIR="${1:-/tmp/batch-coder-tasks}"
DONE_DIR="$TASK_DIR/done"
CHECKPOINT_TAG="last_good_checkpoint"

log() { echo -e "\n\033[1;34m[RUNNER]\033[0m $1"; }

alert() {
    local TYPE="$1"
    local VOLUME=65536
    local -A AUDIO=(
        ["SUCCESS"]="/usr/share/sounds/freedesktop/stereo/phone-incoming-call.oga"
        ["ERROR"]="/usr/share/sounds/freedesktop/stereo/phone-outgoing-busy.oga"
    )
    local -A ANNOUNCE=(
        ["SUCCESS"]='The queue is empty and the machines are quiet. I am suspicious.'
        ["ERROR"]='A task has failed. It will not fix itself. Intervention required.'
    )

    if [[ -f "${AUDIO[$TYPE]:-}" ]]; then
        paplay --volume "$VOLUME" "${AUDIO[$TYPE]}" 2>/dev/null || true
    fi

    if command -v pico2wave >/dev/null 2>&1 && command -v aplay >/dev/null 2>&1; then
        local msg="${ANNOUNCE[$TYPE]:-Attention required}"
        pico2wave -l en-GB -w /tmp/out.wav ", , , $msg" 2>/dev/null && \
            aplay -q /tmp/out.wav 2>/dev/null && \
            rm -f /tmp/out.wav || true
    fi
}

fail() {
    echo -e "\n\033[1;31m[FAILED]\033[0m $1"
    echo -e "\033[1;33m[RECOVERY]\033[0m The damage is contained. To roll back the bad edits from this task, run:"
    echo -e "  git reset --hard $CHECKPOINT_TAG && git clean -fd"
    echo -e "To resume after fixing, just re-run: $0 \"$TASK_DIR\"\n"
    echo -e "\033[1;35m[AGENT INSTRUCTION]\033[0m 🛑 Deadlock Vimes dictates: The worker has failed. Read the error above, investigate the project files natively, fix the issue, and re-run this script to resume the queue."
    alert ERROR
    exit 1
}

mkdir -p "$DONE_DIR"

if [ -n "$(git status --porcelain)" ]; then
    log "The workspace is dirty. Committing what was left behind before starting."
    git add .
    git commit -m "chore: snapshot workspace before task runner batch" || true
fi

git tag -f "$CHECKPOINT_TAG" HEAD

shopt -s nullglob
PENDING_TASKS=("$TASK_DIR"/*.md)
shopt -u nullglob

if [ ${#PENDING_TASKS[@]} -eq 0 ]; then
    log "No pending tasks found. The queue is empty: either the work is done or no one assigned any. Closing up shop."
    exit 0
fi

log "The queue, in order of suffering:"
for pt in "${PENDING_TASKS[@]}"; do
    echo " - $(basename "$pt")"
done

for task_file in "${PENDING_TASKS[@]}"; do
    task_name=$(basename "$task_file")
    log "=========================================================="
    log "Starting task: $task_name"
    log "=========================================================="

    TARGET_FILES=$(grep -oE '`[a-zA-Z0-9_./\-]+`' "$task_file" 2>/dev/null | tr -d '`' | while read -r f; do
        [ -f "$f" ] && echo "$f"
    done | sort -u | tr '\n' ' ')

    TEMP_PROMPT="/tmp/aider_active_task.md"
    cat "$task_file" > "$TEMP_PROMPT"
    cat << 'EOF' >> "$TEMP_PROMPT"

---
You are a contracted coder on a tight deadline. Do the job properly; the inspector is watching.

CRITICAL EXECUTION RULES (non-negotiable):
1. Do not ask the user to add files to the chat. All necessary files have been provided or may be created.
2. Emit your *SEARCH/REPLACE blocks* directly for every file that needs changes to complete this task.
3. If a validation hook was provided, it runs automatically after your edits. Fix all compiler, build, and test errors it reports before finishing.
4. Before completing this task, update `PROGRESS.md`:
   - Check off or add this completed task under `## Completed`.
   - Update `## Current Sprint` to reflect the active milestone.

**IMPORTANT**:
## Reasoning & Planning Rules
Keep internal thinking/reasoning concise (under 300 words).
Do not engage in repetitive loops or meta-deliberation over diff formats.
Quickly decide on the implementation details and begin emitting the final code/diffs immediately.
EOF

    # The agent may have left a validation hook in the scratch directory. If so, we will use it; if not, Aider proceeds without one.
    VALIDATE_SCRIPT="$TASK_DIR/validate.sh"
    if [ -f "$VALIDATE_SCRIPT" ]; then
        AIDER_TEST_ARGS=("--test-cmd" "$VALIDATE_SCRIPT" "--auto-test")
    else
        AIDER_TEST_ARGS=()
    fi

    # Hand the task to Aider, with the validation hook attached if one exists.
    aider \
        $TARGET_FILES \
        PROGRESS.md \
        --message-file "$TEMP_PROMPT" \
        "${AIDER_TEST_ARGS[@]}" \
        --yes-always \
        --exit || fail "Aider failed or could not resolve build errors on: $task_name"

    # Seal the task: run the hook one last time, then commit what survived.
    if [ -f "$VALIDATE_SCRIPT" ]; then
        "$VALIDATE_SCRIPT" || fail "Validation failed on final check for: $task_name"
    fi

    if [ -n "$(git status --porcelain)" ]; then
        git add .
        git commit -m "feat(auto): verify and seal $task_name" || true
    fi

    git tag -f "$CHECKPOINT_TAG" HEAD
    mv "$task_file" "$DONE_DIR/"
    log "Verified and archived: $task_name -> $DONE_DIR/$task_name. It worked. I am noting this down so someone can be surprised later."
done

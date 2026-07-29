# Driver Interaction and Native Capabilities

The go-workflow skills are shared by multiple agent surfaces. Describe the
required outcome and let the active surface bind it to native capabilities.
Never substitute a tool name from another surface.

## Decisions and Missing Intent

When the workflow needs a decision, first use repository, issue, pull request,
configuration, and prior user-message evidence when that evidence determines
the answer.

When required intent cannot be inferred safely:

1. Request it through the active surface's native structured-input capability
   when one is available.
2. If structured input is unavailable, ask the concise question in the final
   response and stop the workflow.
3. Before that final response, preserve the current phase of any active loop
   state and pause it:

   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
   pause_loop_for_driver "$ACTIVE_LOOP_STATE_FILE" "<missing intent>"
   ```

   Use the active workflow's state-file variable in place of
   `ACTIVE_LOOP_STATE_FILE`. When the driver answers, call
   `resume_loop_after_driver` on the same file before continuing. If the
   workflow has other durable state but no active loop, persist an incomplete
   result and reason there.
4. Do not advance the phase, perform dependent actions, emit a completion
   marker, or claim completion until the answer arrives.

Apply those stop rules to every instruction in a shared skill that says to ask,
confirm, choose, or request guidance.

## Planning

Use the active surface's native planning capability when available. Otherwise,
write an explicit implementation plan, keep it updated, and continue from that
plan.

## Delegation

Use the active surface's native delegation capability for fresh-context or
parallel work. Preserve every synchronous, background, model, and
session-lifetime constraint stated by the calling workflow. If delegation is
unavailable, perform the work in the current context unless an independent
review is an explicit completion requirement; in that case, record the
incomplete result and stop.

# Delay Approval Until Wizard Finish

## Problem

When a Discourse instance has both `must_approve_users` and `invite_only` enabled, every new signup lands in the admin review queue and cannot log in until an admin approves them. If the site also uses a custom wizard with `after_signup=true` for verification (e.g. asking the user to fill out fields the admin needs to decide whether to approve them), the admin is stuck:

1. The user signs up and is queued for review with no useful data attached.
2. To let the user reach the wizard, the admin must approve them blindly.
3. After the user finishes the wizard, the admin has to manually re-check the submission and decide whether to keep or reject the user — but the user is already approved and has full forum access.

This flow defeats the point of the verification wizard. The admin has no leverage at the moment of decision, and unwanted users have a window of full access between approval and manual rejection.

## Goal

Add a new wizard option, `delay_approval_until_finish`, that supports the inverse flow:

1. The user signs up.
2. They are temporarily approved so they can log in and reach the wizard, but **only the wizard URL works** — every other page redirects to the wizard, and forum content is blocked at the API layer.
3. They fill out the wizard. Skipping is not allowed.
4. On wizard completion, their approval is revoked and a fresh `ReviewableUser` is created. They are signed out.
5. The admin sees them in the review queue with the wizard submission data attached, makes an informed decision, and approves or rejects.

Admin lockout must be avoided at every layer: staff are exempt from the lockdown, and the temp-approval hook does not fire for staff signups.

## Non-goals

- Changing the existing `after_signup` flow when `delay_approval_until_finish` is false. The current behavior (admin-approves → user reaches wizard) is preserved as the default.
- Building a new admin review UI. We reuse Discourse's existing review queue and link to the wizard submission from the reviewable's payload.
- Supporting guest wizards. Delayed approval is meaningless for non-user actors.

## Design

### Wizard schema

A new boolean `delay_approval_until_finish` on the wizard template, alongside `after_signup`, `required`, etc. It is only meaningful when:
- `after_signup=true` on this wizard, **and**
- the site has `must_approve_users` or `invite_only` enabled

When the admin enables `delay_approval_until_finish` while saving a wizard, the validator forces `required=true` (skipping must be impossible) and rejects the save if `after_signup=false`.

### User marker

A user custom field `delayed_approval_wizard_id` holds the wizard id that put the user into the lockdown window. Set at signup, removed at wizard completion (and at template deletion). All access checks read this field — they do not re-derive the state from current wizard config — so an admin disabling the option mid-flow does not free the user from lockdown.

### Lifecycle

#### A. Signup → temp approval

We hook **two** events with the same handler:

- `:user_created` — fires `after_commit on: :create` for fresh signups (password, OAuth, invite, magic link).
- `:user_unstaged` — fires when a previously staged user becomes a real user via signup. `User#unstage!` is an `update`, not a `create`, so `:user_created` does not fire for these. Without this listener, staged-user signups would skip temp approval and end up locked out at login.

The shared handler:

1. Returns immediately if `user.staff?` (admin lockout protection).
2. Returns if `user.approved?` is already true (e.g. API-created or auto-approved by email domain).
3. Looks up the active `after_signup` wizard. Returns if none, or if it doesn't have `delay_approval_until_finish=true`.
4. Calls `ReviewableUser.set_approved_fields!(user, Discourse.system_user)` and saves.
5. Sets `user.custom_fields["delayed_approval_wizard_id"] = wizard.id` and saves custom fields.

Because the user is now `approved=true` when `EmailToken.confirm` later runs `user.create_reviewable`, that method short-circuits at line 1816 of `app/models/user.rb` (`return if approved?`) and no `ReviewableUser` is created during the wizard window.

The existing `:user_approved` handler in plugin.rb stays as-is. It only matters for the legacy non-delayed flow.

#### B. Login

Login proceeds normally because `user.approved=true`. The `session_controller#login_not_approved_for?` check passes. OAuth, password, magic link, and passkey paths are all covered transparently because they all rely on the same `approved?` flag.

#### C. Lockdown enforcement

Two layers, both deny by default for users with the marker, both bypass for staff.

**Layer 1: HTML navigation lockdown (existing `redirect_to_wizard_if_required`, extended)**

Add a stricter branch in the existing before_action: if `current_user.custom_fields["delayed_approval_wizard_id"].present?` and the user is not staff, ignore `SiteSetting.wizard_redirect_exclude_paths` (no admin escape paths) and unconditionally redirect HTML requests to `/w/<wizard-id>`. The only exempted paths are:

- The wizard itself (`/w/<wizard-id>` and sub-paths) — otherwise we'd loop
- `/session` and `/session/*` (login/logout endpoints — used after revocation to log the user out)
- `/logout` — same reason
- The `/login` SPA route — so the post-revocation redirect target works

These exceptions are the minimum needed to (a) let the user complete the wizard, and (b) let the post-completion redirect-to-login flow work.

**Layer 2: Guardian content denial (`lib/custom_wizard/extensions/guardian.rb`)**

Add overrides that return false when the current user is in the delayed-approval window:

- `can_see_topic?`
- `can_see_post?`
- `can_create_post?`
- `can_send_private_message?`
- `can_edit_user?` (when target is self — blocks profile editing outside the wizard)

Wrap all of these with `return false if in_delayed_approval_window?; super`. Define `in_delayed_approval_window?` as `@user.present? && !@user.staff? && @user.custom_fields["delayed_approval_wizard_id"].present?`.

**What stays open** (intentionally — the wizard SPA needs them):

- The wizard's own routes (`/w/<id>`, `/w/<id>/steps/<step_id>`)
- All `/uploads/*` endpoints (file/image fields, profile pic upload)
- Autocomplete/lookup endpoints: `/u/search/users`, `/tags/filter/search`, `/categories.json`, `/realtime-validations`, hashtag search
- SPA bootstrap: `/site.json`, `/session/current.json`, `/categories_and_latest`
- Composer drafts (`/draft.json`) — used by the wizard's composer field

The Guardian denylist is at the **content** layer, not the path layer, so future endpoints that don't expose forum content keep working without an allowlist update.

**Limits we accept:**
- Category and group names visible via `/site.json` (these are normally public).
- For users with no prior session, the notifications panel is empty so there's nothing to leak.

#### D. Skip blocking

Two enforcement points so the protection holds even if a client crafts a direct request:

1. **`app/controllers/custom_wizard/wizard.rb#skip`**: at the top of the action, if `current_user.custom_fields["delayed_approval_wizard_id"] == params[:wizard_id].underscore`, return 403 with `wizard.delayed_approval.cannot_skip` regardless of the wizard's `required` flag.

2. **Validator (`lib/custom_wizard/validators/template.rb`)**: when saving a wizard with `delay_approval_until_finish=true`, force `required=true` server-side. This makes the existing JS skip-button visibility check (`if (this.required && !this.completed && this.permitted) return;`) hide the button — no frontend change needed.

#### E. Wizard completion → revocation

In `lib/custom_wizard/wizard.rb#cleanup_on_complete!`, after the existing redirect and submission logic:

```ruby
def cleanup_on_complete!
  was_in_delayed_approval = delayed_approval_pending?
  remove_user_redirect

  if current_submission.present?
    current_submission.submitted_at = Time.now.iso8601
    current_submission.save
  end

  trigger_delayed_approval_revocation if was_in_delayed_approval
  update!
end

def delayed_approval_pending?
  user.present? && user.custom_fields["delayed_approval_wizard_id"] == id
end

def trigger_delayed_approval_revocation
  user.approved = false
  user.approved_by_id = nil
  user.approved_at = nil
  user.save!
  user.custom_fields.delete("delayed_approval_wizard_id")
  user.save_custom_fields(true)
  Jobs.enqueue(:create_user_reviewable, user_id: user.id)
end
```

`Jobs::CreateUserReviewable` is the same job Discourse already runs at signup. It checks `must_approve_users?` / `invite_only?` and creates a `ReviewableUser` with the right reason. The user shows up in the admin review queue exactly like a normal pending signup — with the wizard submission accessible at `/admin/wizards/submissions/<wizard-id>/<user-id>` (the existing admin submissions page).

#### F. Sign-out at completion

In `app/controllers/custom_wizard/steps.rb#update`, before calling `cleanup_on_complete!`, snapshot whether the wizard is in delayed-approval mode for this user (read it from `@wizard.delayed_approval_pending?`). After cleanup, if the snapshot was true:

- Call `log_off_user` (the no-arg controller method from `Discourse::CurrentUser`, which delegates to `current_user_provider.log_off_user(session, cookies)`).
- Set `result[:redirect_on_complete] = "/login"` so the existing wizard JS `CustomWizard.finished` redirects there. After log-off the user has no session; visiting `/login` shows the standard login form, and any subsequent login attempt fires Discourse's existing `login_not_approved` UX (because we just set `approved=false`).

The frontend already handles `redirect_on_complete` and uses `DiscourseURL.redirectTo` — no JS changes needed.

### Linking the reviewable to the wizard submission

Listen to `:reviewable_created` in the plugin. If the target user has a wizard submission for the just-finished delayed-approval wizard (find it via `CustomWizard::Submission.list`), append `wizard_submission_url` to `reviewable.payload` (the URL points to the existing admin submissions page at `/admin/wizards/submissions/<wizard-id>`) and save the reviewable.

Surface this to the admin via a small Glimmer/Ember connector at `assets/javascripts/discourse/connectors/reviewable-user-extra/wizard-submission-link.{js,hbs}`. The connector reads `reviewable.payload.wizard_submission_url` and renders a "View wizard submission" link if present.

If the `reviewable-user-extra` outlet doesn't exist in the current Discourse version, the payload field is still present in the reviewable JSON and any admin JS panel can pull it from there — verify the outlet exists during implementation and pick the closest available outlet (e.g., `admin-user-details`) if not.

### Cleanup on wizard delete

`CustomWizard::Template.remove` already calls `clear_user_wizard_redirect` to drop `redirect_to_wizard` custom fields pointing at the deleted wizard. We extend it: for any user holding `delayed_approval_wizard_id == this_wizard_id`, run the same revocation flow as wizard completion (revoke approval, create reviewable, delete the custom field) before the standard removal. This avoids leaving "secretly approved" users behind.

This is documented as expected behavior: "Deleting a delayed-approval wizard while users are mid-flow will revoke their approval and place them in the admin review queue, even if they hadn't finished the wizard."

### Edge cases

| Case | Behavior |
|---|---|
| Staff signs up via this flow | `:user_created` hook returns early. User is approved normally, no marker, no lockdown. |
| User with the marker becomes staff (via API/console) | `in_delayed_approval_window?` returns false because of the staff short-circuit. They are released immediately, no further action needed. |
| Existing user (already approved) when wizard is added | The hook only fires `:user_created`. Existing users are unaffected. |
| Email confirmation pending | Hook fires at user creation, before email confirmation. Approval is set early; email confirmation runs later and `create_reviewable` no-ops because `approved?` is true. |
| Invite redemption | `InviteRedeemer` calls `User.create!`, which fires `:user_created`, so the same hook covers invite signups. |
| Staged-user signup | `User#unstage!` is an `update`, not a `create`, so `:user_created` does not fire. The `:user_unstaged` listener (registered alongside `:user_created` with the same handler) covers this path. |
| Wizard config change mid-flow (admin disables `delay_approval_until_finish`) | User keeps the marker (snapshotted at signup). Lockdown stays in effect; revocation still happens at completion. |
| User abandons wizard, returns later | Session valid → HTML lockdown bounces them to wizard. Session expired → login succeeds (still approved=true), then HTML lockdown bounces to wizard. |
| Plugin disabled mid-flow | Existing users with the marker are stuck at "approved with marker, but plugin code not loaded." Documented limitation; admin can run a console command to clear markers and re-queue users for review. |

## Files touched

### New behavior

| File | Change |
|---|---|
| `plugin.rb` | Add `:user_created` and `:user_unstaged` handlers (shared logic), extend the existing redirect-to-wizard before_action with the delayed-approval lockdown branch, wire `:reviewable_created` listener for submission linking |
| `lib/custom_wizard/wizard.rb` | Add `delay_approval_until_finish` to attr_accessor and constructor, add `delayed_approval_pending?`, `trigger_delayed_approval_revocation`, extend `cleanup_on_complete!` |
| `lib/custom_wizard/extensions/guardian.rb` | Add `in_delayed_approval_window?` and content-denial overrides |
| `lib/custom_wizard/validators/template.rb` | Validate `delay_approval_until_finish` requires `after_signup=true`; force `required=true` |
| `lib/custom_wizard/template.rb` | Extend `remove` to revoke approval and clear markers for in-flight users |
| `app/controllers/custom_wizard/admin/wizard.rb` | Add `delay_approval_until_finish` to permitted save params |
| `app/controllers/custom_wizard/wizard.rb` | Reject `skip` action for delayed-approval users with 403 |
| `app/controllers/custom_wizard/steps.rb` | After `cleanup_on_complete!`, log off the user and set redirect target if delayed approval was active |
| `assets/javascripts/discourse/lib/wizard-schema.js` | Add `delay_approval_until_finish` to `wizard.basic` defaults |
| `assets/javascripts/discourse/templates/admin-wizards-wizard-show.hbs` | Add the new checkbox setting block, conditionally shown when `wizard.after_signup` is true |
| `config/locales/client.en.yml` | Add `delay_approval_until_finish`, `delay_approval_until_finish_label`, `delayed_approval.cannot_skip`, `delayed_approval.locked_out` strings |

### Optional UI

| File | Change |
|---|---|
| `assets/javascripts/discourse/connectors/reviewable-user-extra/wizard-submission-link.{js,hbs}` | Show "View wizard submission" link on the reviewable user view in admin |

### Tests

| File | Coverage |
|---|---|
| `spec/extensions/users_controller_spec.rb` | Signup hook: temp-approve + marker set when delay-approval wizard exists |
| `spec/extensions/invites_controller_spec.rb` | Invite signup goes through the same flow |
| `spec/components/custom_wizard/delayed_approval_spec.rb` (new) | Hook no-ops for staff, no-ops without a delay-approval wizard, no-ops when already approved; revocation flow; template removal flow |
| `spec/requests/custom_wizard/wizard_controller_spec.rb` | `skip` endpoint returns 403 for delayed-approval users; lockdown redirects HTML requests; staff bypass |
| `spec/components/custom_wizard/wizard_spec.rb` | `cleanup_on_complete!` revokes approval, removes custom field, enqueues `Jobs::CreateUserReviewable` |
| `spec/extensions/guardian_spec.rb` (new or extended) | Content-denial overrides return false in the window, true otherwise; staff exempt |
| `spec/components/custom_wizard/template_spec.rb` | `remove` revokes in-flight users and re-queues them for review |
| `spec/components/custom_wizard/template_validator_spec.rb` | Validator forces `required=true` and rejects when `after_signup=false` |

## Testing strategy

Use TDD per the project conventions: write the failing spec for each behavior first, then the implementation. Wherever the existing spec file already covers a related case, add the new case alongside rather than creating a new file. Use `fab!` per the Discourse CLAUDE.md.

A small system spec (Capybara) is worthwhile to verify the end-to-end flow: enable `must_approve_users`, create a delay-approval wizard, sign up a user, walk through the wizard, observe revocation and redirect to login. Place at `spec/system/delayed_approval_wizard_spec.rb`.

## Open questions

None — all clarifying questions resolved during brainstorming.

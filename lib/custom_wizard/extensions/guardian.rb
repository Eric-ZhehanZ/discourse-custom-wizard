# frozen_string_literal: true

# Delayed-approval lockdown:
#
# Users in the delayed-approval window (signed up but not yet finished the
# verification wizard) are temp-approved so they can log in and reach the wizard,
# but must not be able to consume or produce forum content. We deny content access
# at the Guardian layer (not by URL allowlist) so that:
#
#   - The wizard's own routes, uploads, autocomplete, and SPA bootstrap endpoints
#     stay open without per-task allowlist maintenance.
#   - Direct API/JSON requests are blocked at the same gate that HTML rendering
#     uses, so a crafted request can't bypass the HTML lockdown.
#
# The denylist is intentionally narrow and targets the upstream content gates
# (`can_see_topic?`, `can_see_post?`, `can_create_post?`, `can_send_private_message?`).
# Downstream operations like `can_like?`, `can_bookmark?`, and reaction endpoints
# are funneled through `can_see_post?` in core, so blocking the upstream gate is
# sufficient.
#
# Self-edit is deliberately NOT handled at the Guardian layer: core Discourse
# uses `can_edit_user?` as the permission check for several user-scoped READ
# endpoints (notably `UsersController#private_message_topic_tracking_state`,
# which the Ember bootstrap fetches on every page load). Overriding it here
# would make those reads 403 and surface the generic "You are not permitted
# to view the requested resource" popup as soon as the user lands on the
# wizard page. The actual profile-update threat is handled at the controller
# level in `CustomWizardUsersController#update`, which is a write-only gate
# and does not affect data-read endpoints.
#
# Acknowledged gaps (per the design spec):
#   - Category and group names visible via `/site.json` (normally public anyway).
#   - The notifications panel is empty for users with no prior session.
module CustomWizardGuardian
  def can_edit_topic?(topic)
    wizard_can_edit_topic?(topic) || super
  end

  def wizard_can_edit_topic?(topic)
    created_by_wizard = !!topic.wizard_submission_id
    (
      is_my_own?(topic) && created_by_wizard && can_see_topic?(topic) &&
        can_create_post_on_topic?(topic)
    )
  end

  def in_delayed_approval_window?
    return false if @user.blank?
    return false if @user.try(:staff?)
    @user.custom_fields["delayed_approval_wizard_id"].present?
  end

  def can_see_topic?(topic, hide_deleted = true)
    return false if in_delayed_approval_window?
    super
  end

  def can_see_post?(post)
    return false if in_delayed_approval_window?
    super
  end

  def can_create_post?(parent)
    return false if in_delayed_approval_window?
    super
  end

  def can_send_private_message?(target, notify_moderators: false)
    return false if in_delayed_approval_window?
    super
  end
end

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
# (`can_see_topic?`, `can_see_post?`, `can_create_post?`, `can_send_private_message?`,
# self-edit `can_edit_user?`). Downstream operations like `can_like?`, `can_bookmark?`,
# and reaction endpoints are funneled through `can_see_post?` in core, so blocking
# the upstream gate is sufficient.
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

  def can_edit_user?(user)
    return false if in_delayed_approval_window? && user && @user.id == user.id
    super
  end
end

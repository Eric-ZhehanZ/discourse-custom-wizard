# frozen_string_literal: true

# Captures an action whose `requires_review` flag is set, creating a
# ReviewableCustomWizardAction so a staff member can approve/reject the
# effect before it lands on the user.
module CustomWizard::PendingAction
  def self.enqueue(action_template:, wizard:, submission:)
    user = wizard&.user
    return nil if user.blank?
    return nil if action_template.blank?

    fields_snapshot =
      begin
        submission&.fields_and_meta&.to_h&.deep_dup || {}
      rescue StandardError
        {}
      end

    # If the same user already has a pending reviewable for this exact
    # action in this wizard, supersede it with the new snapshot — the
    # latest submission wins.
    existing =
      ReviewableCustomWizardAction.pending.where(
        target_id: user.id,
        target_type: "User",
      )
    existing =
      existing.where(
        "payload ->> 'wizard_id' = ? AND payload -> 'action' ->> 'id' = ?",
        wizard.id,
        action_template["id"],
      )
    existing.find_each { |r| r.update!(status: Reviewable.statuses[:ignored]) }

    Reviewable.transaction do
      reviewable =
        ReviewableCustomWizardAction.new(
          created_by: user,
          target: user,
          target_created_by_id: user.id,
          reviewable_by_moderator: true,
          payload: {
            "wizard_id" => wizard.id,
            "submission_id" => submission&.id,
            "submission_fields" => fields_snapshot,
            "action" => action_template,
          },
        )

      if reviewable.save
        reviewable.add_score(
          Discourse.system_user,
          ReviewableScore.types[:needs_approval],
          reason: "custom_wizard_action",
          force_review: true,
        )
        reviewable
      end
    end
  end
end

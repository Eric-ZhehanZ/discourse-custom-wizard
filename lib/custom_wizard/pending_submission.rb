# frozen_string_literal: true

# Bundles every action of one wizard submission whose template flagged
# `requires_review` into a single ReviewableCustomWizardSubmission row.
# A new submission for the same (user, wizard) supersedes any earlier
# pending row so the latest take wins.
module CustomWizard::PendingSubmission
  def self.enqueue(actions:, wizard:, submission:)
    user = wizard&.user
    return nil if user.blank?
    return nil if actions.blank?

    fields_snapshot =
      begin
        submission&.fields_and_meta&.to_h&.deep_dup || {}
      rescue StandardError
        {}
      end

    # Supersede prior pending row for this user+wizard so re-submissions
    # void earlier reviews not yet acted on.
    existing =
      ReviewableCustomWizardSubmission.pending.where(
        target_id: user.id,
        target_type: "User",
      ).where("payload ->> 'wizard_id' = ?", wizard.id)
    existing.find_each { |r| r.update!(status: Reviewable.statuses[:ignored]) }

    Reviewable.transaction do
      reviewable =
        ReviewableCustomWizardSubmission.new(
          created_by: user,
          target: user,
          target_created_by_id: user.id,
          reviewable_by_moderator: true,
          payload: {
            "wizard_id" => wizard.id,
            "submission_id" => submission&.id,
            "submission_fields" => fields_snapshot,
            "actions" => actions,
          },
        )

      if reviewable.save
        reviewable.add_score(
          Discourse.system_user,
          ReviewableScore.types[:needs_approval],
          reason: "custom_wizard_submission",
          force_review: true,
        )

        user.custom_fields["wizard_review_state_#{wizard.id}"] = "pending"
        # Hold the user (redirect to the wizard's pending-review page) only
        # when (a) the wizard opts in to gating, AND (b) the user has never
        # had an approved submission for this wizard.
        if wizard.restrict_to_approved && !user.custom_fields["wizard_approved_#{wizard.id}"]
          user.custom_fields["redirect_to_wizard"] = wizard.id
        end
        user.save_custom_fields

        reviewable
      end
    end
  end
end

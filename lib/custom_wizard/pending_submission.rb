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

    # Discourse enforces UNIQUE (type, target_id) on the reviewables
    # table, so re-submissions can't INSERT a second row even with a
    # different status. Instead, find the user's existing row (any
    # status) and overwrite it, resetting to pending. This naturally
    # supersedes both lingering pending rows AND prior denied/approved
    # rows for the same user. Status-change history is still tracked
    # via reviewable_histories.
    Reviewable.transaction do
      reviewable =
        ReviewableCustomWizardSubmission.find_or_initialize_by(
          target_id: user.id,
          target_type: "User",
        )

      reviewable.created_by = user
      reviewable.target = user
      reviewable.target_created_by_id = user.id
      reviewable.reviewable_by_moderator = true
      reviewable.payload = {
        "wizard_id" => wizard.id,
        "submission_id" => submission&.id,
        "submission_fields" => fields_snapshot,
        "actions" => actions,
      }
      reviewable.status = Reviewable.statuses[:pending]
      reviewable.score = 0
      reviewable.reject_reason = nil

      if reviewable.save
        reviewable.add_score(
          Discourse.system_user,
          ReviewableScore.types[:needs_approval],
          reason: "custom_wizard_submission",
          force_review: true,
        )

        user.custom_fields["wizard_review_state_#{wizard.id}"] = "pending"
        # Hold (redirect to wizard) only when the wizard opts in,
        # the user has never been approved for it, AND they aren't
        # staff (admins testing the wizard must not lock themselves
        # out of /admin etc).
        if wizard.restrict_to_approved &&
             !user.custom_fields["wizard_approved_#{wizard.id}"] &&
             !user.staff?
          user.custom_fields["redirect_to_wizard"] = wizard.id
        end
        user.save_custom_fields

        reviewable
      end
    end
  end
end

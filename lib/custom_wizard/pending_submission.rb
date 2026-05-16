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

    # Each submission gets its own reviewable row so the queue/history
    # shows one record per submission. Prior pending rows for the same
    # (user, wizard) are demoted to "ignored" so a fresh submission
    # voids any earlier review that hasn't been actioned yet — prior
    # approved/rejected rows are kept untouched as audit history.
    #
    # We leave target_id NULL (Postgres treats NULLs as distinct in
    # the UNIQUE(type, target_id) index) so the constraint allows
    # multiple rows per user.
    ReviewableCustomWizardSubmission
      .pending
      .where(created_by_id: user.id)
      .where("payload ->> 'wizard_id' = ?", wizard.id)
      .find_each { |r| r.update!(status: Reviewable.statuses[:ignored]) }

    Reviewable.transaction do
      reviewable =
        ReviewableCustomWizardSubmission.new(
          created_by: user,
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
        # Hold (redirect to wizard) only when the wizard opts in AND
        # the user has never been approved for it. Staff are NOT
        # exempt — they take the wizard like everyone else. /admin is
        # always whitelisted from the redirect so admins can still
        # reach the review queue to approve their own pending row.
        if wizard.restrict_to_approved &&
             !user.custom_fields["wizard_approved_#{wizard.id}"]
          user.custom_fields["redirect_to_wizard"] = wizard.id
        end
        user.save_custom_fields

        reviewable
      end
    end
  end
end

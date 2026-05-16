# frozen_string_literal: true

# One reviewable per wizard submission. Bundles all of the submission's
# actions whose template flagged `requires_review`. Staff approve once →
# every bundled action runs against a snapshot of the submitted fields.
# Reject → no action runs; user is marked denied for that wizard and
# (when the wizard has restrict_to_approved set) is redirected back to
# resubmit before regaining access.
class ReviewableCustomWizardSubmission < Reviewable
  def build_actions(actions, guardian, _args)
    return unless pending?
    return unless guardian.is_staff?

    actions.add(:approve_wizard_submission) do |a|
      a.icon = "check"
      a.label = "reviewables.actions.approve_wizard_submission.title"
      a.description = "reviewables.actions.approve_wizard_submission.description"
    end

    actions.add(:reject_wizard_submission) do |a|
      a.icon = "xmark"
      a.label = "reviewables.actions.reject_wizard_submission.title"
      a.description = "reviewables.actions.reject_wizard_submission.description"
    end
  end

  def perform_approve_wizard_submission(performer, _args)
    apply_pending_actions!
    mark_user_approved!
    notify_user(state: :approved, performer: performer)
    create_result(:success, :approved)
  end

  def perform_reject_wizard_submission(performer, args)
    mark_user_denied!
    notify_user(state: :rejected, performer: performer, reason: args[:reject_reason])
    create_result(:success, :rejected)
  end

  def wizard_id
    payload&.dig("wizard_id")
  end

  def actions_payload
    payload&.dig("actions") || []
  end

  def wizard_template
    @wizard_template ||= CustomWizard::Template.find(wizard_id) if wizard_id
  end

  def wizard_name
    wizard_template&.dig("name") || wizard_id
  end

  private

  def review_user
    @review_user ||= created_by || (target.is_a?(User) ? target : nil)
  end

  def submission_fields
    payload&.dig("submission_fields") || {}
  end

  def apply_pending_actions!
    return if review_user.blank? || wizard_id.blank? || actions_payload.empty?

    builder = CustomWizard::Builder.new(wizard_id, review_user)
    wizard = builder.build
    return unless wizard

    submission = CustomWizard::Submission.new(wizard, submission_fields)

    actions_payload.each do |action_template|
      # JSON round-tripping flattens HashWithIndifferentAccess back to a
      # plain Hash with string keys, but CustomWizard::Action mixes
      # symbol and string lookups (e.g. profile_updates.first[:pairs]).
      # Re-wrap so both forms keep working, matching what
      # CustomWizard::Template#normalize_data does for live submissions.
      indifferent = action_template.is_a?(Hash) ? action_template.with_indifferent_access : action_template

      CustomWizard::Action.new(
        action: indifferent,
        wizard: wizard,
        submission: submission,
      ).perform
    end
  end

  def mark_user_approved!
    return unless review_user

    # Use a fresh User instance so any validation errors accumulated on
    # `review_user` during action replay don't trip save_custom_fields.
    fresh = User.find(review_user.id)
    fresh.custom_fields["wizard_approved_#{wizard_id}"] = true
    fresh.custom_fields["wizard_review_state_#{wizard_id}"] = "approved"
    if fresh.custom_fields["redirect_to_wizard"].to_s == wizard_id.to_s
      fresh.custom_fields.delete("redirect_to_wizard")
    end
    fresh.save_custom_fields

    # Close out the open submission so the user starts fresh next time
    # (this is what cleanup_on_complete! does for non-review wizards;
    # we deferred it until the review decision lands).
    begin
      builder = CustomWizard::Builder.new(wizard_id, fresh)
      wiz = builder.build
      sub = wiz&.current_submission
      if sub && !sub.submitted_at
        sub.submitted_at = Time.now.iso8601
        sub.save
      end
    rescue StandardError => e
      Rails.logger.warn("custom_wizard: failed to close submission for user #{fresh.id}: #{e.class}: #{e.message}")
    end
  end

  def mark_user_denied!
    return unless review_user

    fresh = User.find(review_user.id)
    fresh.custom_fields["wizard_review_state_#{wizard_id}"] = "denied"
    fresh.custom_fields.delete("wizard_approved_#{wizard_id}")
    # Never force staff back to the wizard — they'd lock themselves out
    # of the admin UI they need to manage the queue.
    fresh.custom_fields["redirect_to_wizard"] = wizard_id unless fresh.staff?
    fresh.save_custom_fields
  end

  def notify_user(state:, performer: nil, reason: nil)
    return unless review_user

    message_type =
      state == :approved ? :custom_wizard_review_approved : :custom_wizard_review_denied
    reason_text = reason.to_s.strip.presence

    SystemMessage.create(
      review_user,
      message_type,
      wizard_name: wizard_name,
      wizard_id: wizard_id,
      wizard_url: "/w/#{wizard_id}",
      reason: reason_text || I18n.t("system_messages.custom_wizard_review_denied.no_reason"),
    )
  rescue StandardError => e
    Rails.logger.warn(
      "custom_wizard: failed to send review #{state} notification to user #{review_user.id}: #{e.class}: #{e.message}",
    )
  end
end

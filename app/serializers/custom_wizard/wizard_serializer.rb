# frozen_string_literal: true

class CustomWizard::WizardSerializer < CustomWizard::BasicWizardSerializer
  attributes :start,
             :background,
             :submission_last_updated_at,
             :theme_id,
             :completed,
             :required,
             :permitted,
             :resume_on_revisit,
             :pending_review,
             :previously_approved,
             :recently_approved

  has_many :steps, serializer: ::CustomWizard::StepSerializer, embed: :objects
  has_one :user, serializer: ::BasicUserSerializer, embed: :objects

  def completed
    object.completed?
  end

  def include_completed?
    object.completed? &&
      (!object.respond_to?(:multiple_submissions) || !object.multiple_submissions) &&
      !scope.is_admin?
  end

  def permitted
    object.permitted?
  end

  def start
    object.start
  end

  def include_start?
    include_steps? && object.start.present?
  end

  def submission_last_updated_at
    object.current_submission.updated_at
  end

  def include_steps?
    !include_completed?
  end

  def pending_review
    object.user&.custom_fields&.[]("wizard_review_state_#{object.id}") == "pending"
  end

  def previously_approved
    !!object.user&.custom_fields&.[]("wizard_approved_#{object.id}")
  end

  # True only on the first wizard page-load after the user's most recent
  # submission was approved. The wizard page uses this to swap the form
  # for a one-time "submission approved — go to the site" screen.
  # We flip the seen marker as part of serialization so the next load
  # falls through to the normal form (re-submission flow).
  def recently_approved
    return false unless object.user

    state = object.user.custom_fields["wizard_review_state_#{object.id}"]
    return false unless state == "approved"
    seen = object.user.custom_fields["wizard_approved_seen_#{object.id}"]
    return false if seen

    # Mark seen so the next visit shows the form.
    object.user.custom_fields["wizard_approved_seen_#{object.id}"] = true
    begin
      object.user.save_custom_fields
    rescue StandardError
      # If save_custom_fields raises (e.g. user has unrelated validation
      # errors), still tell the client recently_approved=true — they get
      # the message once, and we'll just try to flip the marker again
      # next time.
    end
    true
  end
end
